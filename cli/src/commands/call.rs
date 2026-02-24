//! Headless audio call: Nostr signaling + GStreamer WebRTC.
//!
//! Implements the same call protocol as the Flutter app (kinds 25050-25054,
//! NIP-59 gift wrapping) but runs headless for AI agent use.
//!
//! Without the `webrtc` feature, only signaling is performed (useful for
//! testing the protocol without GStreamer). With `webrtc`, a full GStreamer
//! pipeline handles WebRTC + Opus audio.

use anyhow::{Context, Result};
use nostr_sdk::prelude::*;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Notify;

use crate::config;
use crate::relay::pool;
use crate::storage::file_store::FileStore;

#[cfg(feature = "webrtc")]
use crate::webrtc::{WebRtcEvent, WebRtcSession};

// ── Signaling event kinds (matching Flutter app) ───────────────────────────

const KIND_CALL_OFFER: u16 = 25050;
const KIND_CALL_ANSWER: u16 = 25051;
const KIND_ICE_CANDIDATE: u16 = 25052;
const KIND_CALL_END: u16 = 25053;
const KIND_CALL_STATE_UPDATE: u16 = 25054;

// ── Signaling payloads ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallOfferPayload {
    sdp: String,
    call_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallAnswerPayload {
    sdp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct IceCandidatePayload {
    candidate: String,
    sdp_mid: Option<String>,
    sdp_m_line_index: Option<u32>,
}

// ── Call state ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
enum CallState {
    Idle,
    Initiating,
    Ringing,
    Connecting,
    Active,
    Ending,
}

// ── Signaling helpers ──────────────────────────────────────────────────────

fn signaling_tags(
    recipient_pk: &PublicKey,
    call_id: &str,
    call_type: Option<&str>,
) -> Vec<Tag> {
    let expiration = Timestamp::now().as_secs() + 60;
    let mut tags = vec![
        Tag::public_key(*recipient_pk),
        Tag::custom(TagKind::custom("call-id"), vec![call_id.to_string()]),
        Tag::expiration(Timestamp::from(expiration)),
    ];
    if let Some(ct) = call_type {
        tags.push(Tag::custom(
            TagKind::custom("call-type"),
            vec![ct.to_string()],
        ));
    }
    tags
}

async fn gift_wrap_signaling(
    keys: &Keys,
    kind_num: u16,
    content: &str,
    recipient_pk: &PublicKey,
    call_id: &str,
    call_type: Option<&str>,
) -> Result<Event> {
    let tags = signaling_tags(recipient_pk, call_id, call_type);
    let rumor = EventBuilder::new(Kind::from(kind_num), content)
        .tags(tags)
        .build(keys.public_key());

    EventBuilder::gift_wrap(keys, recipient_pk, rumor, Vec::<Tag>::new())
        .await
        .context("Failed to gift-wrap signaling event")
}

fn extract_tag_value(tags: &Tags, name: &str) -> Option<String> {
    for tag in tags.iter() {
        let s = tag.as_slice();
        if s.len() >= 2 && s[0] == name {
            return Some(s[1].clone());
        }
    }
    None
}

#[cfg(feature = "webrtc")]
async fn send_ice_to_relay(
    keys: &Keys,
    client: &Client,
    remote_pk: &PublicKey,
    call_id: &str,
    candidate: &str,
    sdp_m_line_index: u32,
) -> Result<()> {
    let payload = serde_json::to_string(&IceCandidatePayload {
        candidate: candidate.to_string(),
        sdp_mid: Some("0".to_string()),
        sdp_m_line_index: Some(sdp_m_line_index),
    })?;
    let event = gift_wrap_signaling(
        keys,
        KIND_ICE_CANDIDATE,
        &payload,
        remote_pk,
        call_id,
        None,
    )
    .await?;
    client.send_event(&event).await?;
    Ok(())
}

// ── Main entry point ───────────────────────────────────────────────────────

pub async fn run(
    target: String,
    key_path: Option<String>,
    data_dir: Option<String>,
    answer_call_id: Option<String>,
    #[allow(unused_variables)]
    pipe: Option<String>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;
    let kp = key_path
        .map(std::path::PathBuf::from)
        .unwrap_or_else(config::default_key_path);
    let secret = std::fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    // Resolve target pubkey
    let remote_pk = if target.starts_with("npub") {
        PublicKey::from_bech32(&target).context("Invalid npub")?
    } else if target.len() == 64 {
        PublicKey::from_hex(&target).context("Invalid hex pubkey")?
    } else {
        let group = store
            .find_group_by_prefix(&target)?
            .context("Group not found — provide an npub or group ID")?;
        anyhow::bail!(
            "Group calls not yet supported in CLI. Use an npub for 1:1 calls.\nGroup: {}",
            group.name
        );
    };

    // Collect relays from all known groups
    let relay_urls: Vec<String> = {
        let groups = store.load_groups().unwrap_or_default();
        let mut urls: Vec<String> = groups.into_iter().flat_map(|g| g.relay_urls).collect();
        urls.sort();
        urls.dedup();
        if urls.is_empty() {
            anyhow::bail!("No relays configured — join a group first");
        }
        urls
    };
    let client = pool::connect(&keys, &relay_urls).await?;

    let call_id = answer_call_id
        .clone()
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let is_answering = answer_call_id.is_some();

    eprintln!(
        "📞 {} call with {} (call-id: {})",
        if is_answering { "Answering" } else { "Initiating" },
        remote_pk.to_bech32().unwrap_or_else(|_| remote_pk.to_hex()),
        &call_id[..8],
    );

    // ── Create WebRTC session (if feature enabled) ─────────────────────
    #[cfg(feature = "webrtc")]
    let (webrtc_session, mut webrtc_rx) = {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        let session = WebRtcSession::new(pipe.as_deref(), tx)
            .context("Failed to create WebRTC session")?;
        session.start()?;
        (Arc::new(session), rx)
    };

    // ── Subscribe to incoming signaling ────────────────────────────────
    let filter = Filter::new()
        .kind(Kind::GiftWrap)
        .pubkey(keys.public_key())
        .since(Timestamp::now());
    client.subscribe(filter, None).await?;

    let shutdown = Arc::new(Notify::new());

    // ── Forward local ICE candidates to remote (WebRTC only) ───────────
    #[cfg(feature = "webrtc")]
    let _ice_task = {
        let keys = keys.clone();
        let client = client.clone();
        let remote_pk = remote_pk;
        let call_id = call_id.clone();
        let session = webrtc_session.clone();
        let shutdown = shutdown.clone();

        tokio::spawn(async move {
            while let Some(event) = webrtc_rx.recv().await {
                match event {
                    WebRtcEvent::OfferCreated(sdp) => {
                        eprintln!("📤 Sending SDP offer ({} bytes)", sdp.len());
                        let payload = serde_json::to_string(&CallOfferPayload {
                            sdp,
                            call_type: "audio".to_string(),
                        })
                        .unwrap();
                        if let Ok(ev) = gift_wrap_signaling(
                            &keys,
                            KIND_CALL_OFFER,
                            &payload,
                            &remote_pk,
                            &call_id,
                            Some("audio"),
                        )
                        .await
                        {
                            let _ = client.send_event(&ev).await;
                        }
                    }
                    WebRtcEvent::AnswerCreated(sdp) => {
                        eprintln!("📤 Sending SDP answer ({} bytes)", sdp.len());
                        let payload =
                            serde_json::to_string(&CallAnswerPayload { sdp }).unwrap();
                        if let Ok(ev) = gift_wrap_signaling(
                            &keys,
                            KIND_CALL_ANSWER,
                            &payload,
                            &remote_pk,
                            &call_id,
                            None,
                        )
                        .await
                        {
                            let _ = client.send_event(&ev).await;
                        }
                    }
                    WebRtcEvent::IceCandidateGathered(ice) => {
                        let _ = send_ice_to_relay(
                            &keys,
                            &client,
                            &remote_pk,
                            &call_id,
                            &ice.candidate,
                            ice.sdp_m_line_index,
                        )
                        .await;
                    }
                    WebRtcEvent::StateChanged(state) => {
                        eprintln!("🔗 WebRTC state: {}", state);
                    }
                    WebRtcEvent::Error(err) => {
                        eprintln!("❌ WebRTC error: {}", err);
                        shutdown.notify_one();
                    }
                }
            }
        })
    };

    // ── Handle incoming signaling events ───────────────────────────────
    {
        let keys = keys.clone();
        let client = client.clone();
        let call_id = call_id.clone();
        let shutdown = shutdown.clone();
        #[cfg(feature = "webrtc")]
        let session = webrtc_session.clone();

        tokio::spawn(async move {
            client
                .handle_notifications(|notification| {
                    let keys = keys.clone();
                    let client = client.clone();
                    let call_id = call_id.clone();
                    let shutdown = shutdown.clone();
                    #[cfg(feature = "webrtc")]
                    let session = session.clone();

                    async move {
                        if let RelayPoolNotification::Event { event, .. } = notification {
                            if event.kind != Kind::GiftWrap {
                                return Ok(false);
                            }

                            let unwrapped =
                                match UnwrappedGift::from_gift_wrap(&keys, &event).await {
                                    Ok(u) => u,
                                    Err(_) => return Ok(false),
                                };

                            let inner = unwrapped.rumor;
                            let kind_num = inner.kind.as_u16();

                            if kind_num < KIND_CALL_OFFER || kind_num > KIND_CALL_STATE_UPDATE {
                                return Ok(false);
                            }

                            if extract_tag_value(&inner.tags, "call-id").as_deref()
                                != Some(&call_id)
                            {
                                return Ok(false);
                            }

                            match kind_num {
                                KIND_CALL_OFFER => {
                                    if let Ok(payload) =
                                        serde_json::from_str::<CallOfferPayload>(&inner.content)
                                    {
                                        eprintln!(
                                            "📥 Call offer (type: {}, SDP: {} bytes)",
                                            payload.call_type,
                                            payload.sdp.len()
                                        );

                                        #[cfg(feature = "webrtc")]
                                        {
                                            if let Err(e) = session
                                                .set_remote_offer_and_answer(&payload.sdp)
                                                .await
                                            {
                                                eprintln!("❌ Failed to process offer: {}", e);
                                            }
                                        }

                                        #[cfg(not(feature = "webrtc"))]
                                        {
                                            eprintln!(
                                                "   (signaling only — build with --features webrtc)"
                                            );
                                            let answer_payload = serde_json::to_string(
                                                &CallAnswerPayload {
                                                    sdp: "v=0\r\n".to_string(),
                                                },
                                            )
                                            .unwrap();
                                            if let Ok(ev) = gift_wrap_signaling(
                                                &keys,
                                                KIND_CALL_ANSWER,
                                                &answer_payload,
                                                &remote_pk,
                                                &call_id,
                                                None,
                                            )
                                            .await
                                            {
                                                let _ = client.send_event(&ev).await;
                                                eprintln!("📤 Sent placeholder answer");
                                            }
                                        }
                                    }
                                }
                                KIND_CALL_ANSWER => {
                                    if let Ok(payload) =
                                        serde_json::from_str::<CallAnswerPayload>(&inner.content)
                                    {
                                        eprintln!(
                                            "📥 Call answer (SDP: {} bytes)",
                                            payload.sdp.len()
                                        );

                                        #[cfg(feature = "webrtc")]
                                        {
                                            if let Err(e) =
                                                session.set_remote_answer(&payload.sdp)
                                            {
                                                eprintln!(
                                                    "❌ Failed to set remote answer: {}",
                                                    e
                                                );
                                            }
                                        }
                                    }
                                }
                                KIND_ICE_CANDIDATE => {
                                    if let Ok(payload) =
                                        serde_json::from_str::<IceCandidatePayload>(
                                            &inner.content,
                                        )
                                    {
                                        eprintln!(
                                            "📥 ICE: {}",
                                            payload
                                                .candidate
                                                .get(..50)
                                                .unwrap_or(&payload.candidate)
                                        );

                                        #[cfg(feature = "webrtc")]
                                        {
                                            session.add_ice_candidate(
                                                payload.sdp_m_line_index.unwrap_or(0),
                                                &payload.candidate,
                                            );
                                        }
                                    }
                                }
                                KIND_CALL_END => {
                                    eprintln!("📥 Call ended by remote: {}", inner.content);
                                    shutdown.notify_one();
                                    return Ok(true);
                                }
                                KIND_CALL_STATE_UPDATE => {
                                    eprintln!("📥 Remote state update: {}", inner.content);
                                }
                                _ => {}
                            }
                        }
                        Ok(false)
                    }
                })
                .await
        });
    }

    // ── Initiate call (if not answering) ───────────────────────────────
    if !is_answering {
        #[cfg(feature = "webrtc")]
        {
            eprintln!("🔧 Creating WebRTC offer...");
            webrtc_session.create_offer().await?;
            // SDP offer will be sent via the ICE task when OfferCreated event fires
        }

        #[cfg(not(feature = "webrtc"))]
        {
            let offer_payload = serde_json::to_string(&CallOfferPayload {
                sdp: "v=0\r\n".to_string(),
                call_type: "audio".to_string(),
            })?;
            let offer = gift_wrap_signaling(
                &keys,
                KIND_CALL_OFFER,
                &offer_payload,
                &remote_pk,
                &call_id,
                Some("audio"),
            )
            .await?;
            client.send_event(&offer).await?;
            eprintln!("📤 Sent call offer (signaling only)");
        }
    }

    // ── Wait for Ctrl+C or remote hangup ───────────────────────────────
    eprintln!("Press Ctrl+C to end the call");
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            eprintln!("\n📴 Ending call...");
        }
        _ = shutdown.notified() => {
            eprintln!("📴 Remote ended the call.");
        }
    }

    // ── Cleanup ────────────────────────────────────────────────────────
    #[cfg(feature = "webrtc")]
    webrtc_session.stop();

    let hangup = gift_wrap_signaling(
        &keys,
        KIND_CALL_END,
        "hangup",
        &remote_pk,
        &call_id,
        None,
    )
    .await?;
    client.send_event(&hangup).await?;

    eprintln!("✅ Call ended ({})", &call_id[..8]);
    client.disconnect().await;
    Ok(())
}
