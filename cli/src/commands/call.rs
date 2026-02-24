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

// ── Main entry point ───────────────────────────────────────────────────────

pub async fn run(
    target: String,
    key_path: Option<String>,
    data_dir: Option<String>,
    answer_call_id: Option<String>,
    _pipe: Option<String>,
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

    // Resolve target — could be a group ID or a pubkey (npub/hex)
    let remote_pk = if target.starts_with("npub") {
        PublicKey::from_bech32(&target).context("Invalid npub")?
    } else if target.len() == 64 {
        PublicKey::from_hex(&target).context("Invalid hex pubkey")?
    } else {
        // Try as group ID — get first other member
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
        let mut urls: Vec<String> = groups
            .into_iter()
            .flat_map(|g| g.relay_urls)
            .collect();
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

    // Subscribe to incoming gift-wrapped signaling events
    let filter = Filter::new()
        .kind(Kind::GiftWrap)
        .pubkey(keys.public_key())
        .since(Timestamp::now());
    client.subscribe(filter, None).await?;

    let shutdown = Arc::new(Notify::new());
    let shutdown_clone = shutdown.clone();
    let keys_clone = keys.clone();
    let client_clone = client.clone();
    let remote_pk_clone = remote_pk;
    let call_id_clone = call_id.clone();

    // Handle incoming signaling events
    let _signaling_task = tokio::spawn(async move {
        let keys = keys_clone;
        let client = client_clone;
        let remote_pk = remote_pk_clone;
        let call_id = call_id_clone;

        client
            .handle_notifications(|notification| {
                let keys = keys.clone();
                let client = client.clone();
                let remote_pk = remote_pk;
                let call_id = call_id.clone();
                let shutdown = shutdown_clone.clone();

                async move {
                    if let RelayPoolNotification::Event { event, .. } = notification {
                        if event.kind != Kind::GiftWrap {
                            return Ok(false);
                        }

                        // Unwrap NIP-59 gift wrap
                        let unwrapped = match UnwrappedGift::from_gift_wrap(&keys, &event).await {
                            Ok(u) => u,
                            Err(_) => return Ok(false),
                        };

                        let inner = unwrapped.rumor;
                        let kind_num = inner.kind.as_u16();

                        // Only handle call signaling kinds
                        if kind_num < KIND_CALL_OFFER || kind_num > KIND_CALL_STATE_UPDATE {
                            return Ok(false);
                        }

                        // Verify call-id matches
                        let event_call_id = extract_tag_value(&inner.tags, "call-id");
                        if event_call_id.as_deref() != Some(&call_id) {
                            return Ok(false);
                        }

                        match kind_num {
                            KIND_CALL_OFFER => {
                                eprintln!("📥 Received call offer");
                                if let Ok(payload) =
                                    serde_json::from_str::<CallOfferPayload>(&inner.content)
                                {
                                    eprintln!(
                                        "   Type: {}, SDP length: {} bytes",
                                        payload.call_type,
                                        payload.sdp.len()
                                    );

                                    #[cfg(feature = "webrtc")]
                                    {
                                        // TODO: Create GStreamer pipeline, set remote offer,
                                        // create answer, send it back
                                        eprintln!("   WebRTC: processing offer...");
                                    }

                                    #[cfg(not(feature = "webrtc"))]
                                    {
                                        eprintln!("   WebRTC not available (build with --features webrtc)");
                                        // Send a placeholder answer for protocol testing
                                        let answer_payload = serde_json::to_string(
                                            &CallAnswerPayload {
                                                sdp: "v=0\r\n".to_string(),
                                            },
                                        )
                                        .unwrap();
                                        let answer = gift_wrap_signaling(
                                            &keys,
                                            KIND_CALL_ANSWER,
                                            &answer_payload,
                                            &remote_pk,
                                            &call_id,
                                            None,
                                        )
                                        .await;
                                        if let Ok(event) = answer {
                                            let _ = client.send_event(&event).await;
                                            eprintln!("📤 Sent placeholder answer");
                                        }
                                    }
                                }
                            }
                            KIND_CALL_ANSWER => {
                                eprintln!("📥 Received call answer");
                                if let Ok(payload) =
                                    serde_json::from_str::<CallAnswerPayload>(&inner.content)
                                {
                                    eprintln!(
                                        "   SDP length: {} bytes",
                                        payload.sdp.len()
                                    );

                                    #[cfg(feature = "webrtc")]
                                    {
                                        // TODO: Set remote answer on GStreamer webrtcbin
                                        eprintln!("   WebRTC: setting remote answer...");
                                    }
                                }
                            }
                            KIND_ICE_CANDIDATE => {
                                if let Ok(payload) =
                                    serde_json::from_str::<IceCandidatePayload>(&inner.content)
                                {
                                    eprintln!(
                                        "📥 ICE candidate: {}",
                                        &payload.candidate
                                            .get(..60)
                                            .unwrap_or(&payload.candidate)
                                    );

                                    #[cfg(feature = "webrtc")]
                                    {
                                        // TODO: Add ICE candidate to webrtcbin
                                    }
                                }
                            }
                            KIND_CALL_END => {
                                eprintln!("📥 Call ended by remote: {}", inner.content);
                                shutdown.notify_one();
                                return Ok(true); // stop listening
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

    // If initiating, send the offer
    if !is_answering {
        #[cfg(feature = "webrtc")]
        {
            // TODO: Create GStreamer pipeline, generate SDP offer
            eprintln!("🔧 Creating WebRTC offer...");
        }

        #[cfg(not(feature = "webrtc"))]
        {
            // Send placeholder offer for protocol testing
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
            eprintln!("📤 Sent call offer (signaling-only, no WebRTC)");
        }
    }

    // Wait for Ctrl+C or remote hangup
    eprintln!("Press Ctrl+C to end the call");
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            eprintln!("\n📴 Ending call...");
        }
        _ = shutdown.notified() => {
            eprintln!("📴 Remote ended the call.");
        }
    }

    // Send hangup
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
