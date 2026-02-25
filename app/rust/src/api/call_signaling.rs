//! Call signaling over Nostr: create, send, and process WebRTC signaling events.
//!
//! Uses NIP-59 gift wrapping for 1:1 call privacy and Marmot MLS group messages
//! for group call signaling. Event kinds 25050-25055 per Burrow's NIP draft.
//!
//! Event kinds:
//! - 25050: Call Offer (SDP offer + metadata)
//! - 25051: Call Answer (SDP answer)
//! - 25052: ICE Candidate
//! - 25053: Call End/Hangup
//! - 25054: Call State Update (mute, camera toggle)

use flutter_rust_bridge::frb;
use nostr_sdk::prelude::*;
use serde::{Deserialize, Serialize};

use crate::api::error::BurrowError;
use crate::api::state;
use crate::frb_generated::StreamSink;

// ── Event kind constants ───────────────────────────────────────────────────

const KIND_CALL_OFFER: u16 = 25050;
const KIND_CALL_ANSWER: u16 = 25051;
const KIND_ICE_CANDIDATE: u16 = 25052;
const KIND_CALL_END: u16 = 25053;
const KIND_CALL_STATE_UPDATE: u16 = 25054;

// ── FFI-friendly types ─────────────────────────────────────────────────────

/// Payload for a call offer event.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallOfferPayload {
    sdp: String,
    call_type: String, // "audio" or "video"
}

/// Payload for a call answer event.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallAnswerPayload {
    sdp: String,
}

/// Payload for an ICE candidate event.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct IceCandidatePayload {
    candidate: String,
    sdp_mid: Option<String>,
    sdp_m_line_index: Option<u32>,
}

/// Payload for a call state update event.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallStateUpdatePayload {
    is_muted: Option<bool>,
    is_video_enabled: Option<bool>,
}

/// A parsed incoming call signaling event, flattened for FFI.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct CallSignalingEvent {
    /// Event kind (25050-25054).
    pub kind: u32,
    /// Hex-encoded sender public key.
    pub sender_pubkey_hex: String,
    /// Call ID from tags.
    pub call_id: String,
    /// Call type from tags ("audio" or "video"), if present.
    pub call_type: Option<String>,
    /// Event content (JSON payload).
    pub content: String,
    /// Unix timestamp.
    pub created_at: u64,
}

// ── Helper: build signaling event tags ─────────────────────────────────────

fn signaling_tags(
    recipient_pubkey_hex: &str,
    call_id: &str,
    call_type: Option<&str>,
    expiration_secs: u64,
) -> Result<Vec<Tag>, BurrowError> {
    let recipient_pk =
        PublicKey::from_hex(recipient_pubkey_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let mut tags = vec![
        Tag::public_key(recipient_pk),
        Tag::custom(
            TagKind::custom("call-id"),
            vec![call_id.to_string()],
        ),
        Tag::expiration(Timestamp::from(expiration_secs)),
    ];

    if let Some(ct) = call_type {
        tags.push(Tag::custom(
            TagKind::custom("call-type"),
            vec![ct.to_string()],
        ));
    }

    Ok(tags)
}

/// Build and gift-wrap a signaling event (NIP-59) for a 1:1 call.
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059) ready for relay publication.
async fn build_gift_wrapped_signaling(
    kind_num: u16,
    content: &str,
    recipient_pubkey_hex: &str,
    call_id: &str,
    call_type: Option<&str>,
) -> Result<String, BurrowError> {
    let expiration = Timestamp::now().as_secs() + 60; // 60s TTL
    let tags = signaling_tags(recipient_pubkey_hex, call_id, call_type, expiration)?;
    let recipient_pk = PublicKey::from_hex(recipient_pubkey_hex)
        .map_err(|e| BurrowError::from(e.to_string()))?;

    let keys = state::with_state(|s| Ok(s.keys.clone())).await?;

    // Build the inner rumor as unsigned event
    let rumor = EventBuilder::new(Kind::from(kind_num), content)
        .tags(tags)
        .build(keys.public_key());

    // Gift wrap using NIP-59
    let gift_wrap = EventBuilder::gift_wrap(
        &keys,
        &recipient_pk,
        rumor,
        Vec::<Tag>::new(),
    )
    .await
    .map_err(|e| BurrowError::from(e.to_string()))?;

    serde_json::to_string(&gift_wrap).map_err(|e| BurrowError::from(e.to_string()))
}

// ── Public API ──────────────────────────────────────────────────────────────

/// Initiate a call by creating a gift-wrapped call offer event (kind 25050).
///
/// `sdp_offer`: SDP offer string from WebRTC.
/// `call_id`: Unique call identifier (UUIDv4).
/// `call_type`: "audio" or "video".
/// `recipient_pubkey_hex`: Hex-encoded public key of the callee.
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059) to publish to relays.
#[frb]
pub async fn initiate_call(
    sdp_offer: String,
    call_id: String,
    call_type: String,
    recipient_pubkey_hex: String,
) -> Result<String, BurrowError> {
    let payload = serde_json::to_string(&CallOfferPayload {
        sdp: sdp_offer,
        call_type: call_type.clone(),
    })
    .map_err(|e| BurrowError::from(e.to_string()))?;

    build_gift_wrapped_signaling(
        KIND_CALL_OFFER,
        &payload,
        &recipient_pubkey_hex,
        &call_id,
        Some(&call_type),
    )
    .await
}

/// Accept a call by creating a gift-wrapped call answer event (kind 25051).
///
/// `sdp_answer`: SDP answer string from WebRTC.
/// `call_id`: Call identifier from the received offer.
/// `caller_pubkey_hex`: Hex-encoded public key of the caller.
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059).
#[frb]
pub async fn accept_call(
    sdp_answer: String,
    call_id: String,
    caller_pubkey_hex: String,
) -> Result<String, BurrowError> {
    let payload = serde_json::to_string(&CallAnswerPayload { sdp: sdp_answer })
        .map_err(|e| BurrowError::from(e.to_string()))?;

    build_gift_wrapped_signaling(
        KIND_CALL_ANSWER,
        &payload,
        &caller_pubkey_hex,
        &call_id,
        None,
    )
    .await
}

/// Reject an incoming call (kind 25053 with rejection reason).
///
/// `call_id`: Call identifier from the received offer.
/// `caller_pubkey_hex`: Hex-encoded public key of the caller.
/// `reason`: Optional rejection reason (e.g., "busy", "declined").
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059).
#[frb]
pub async fn reject_call(
    call_id: String,
    caller_pubkey_hex: String,
    reason: Option<String>,
) -> Result<String, BurrowError> {
    let content = reason.unwrap_or_else(|| "declined".to_string());

    build_gift_wrapped_signaling(
        KIND_CALL_END,
        &content,
        &caller_pubkey_hex,
        &call_id,
        None,
    )
    .await
}

/// Send an ICE candidate to the remote peer (kind 25052).
///
/// `candidate`: ICE candidate string.
/// `sdp_mid`: SDP media ID.
/// `sdp_m_line_index`: SDP media line index.
/// `call_id`: Call identifier.
/// `remote_pubkey_hex`: Hex-encoded public key of the remote peer.
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059).
#[frb]
pub async fn send_ice_candidate(
    candidate: String,
    sdp_mid: Option<String>,
    sdp_m_line_index: Option<u32>,
    call_id: String,
    remote_pubkey_hex: String,
) -> Result<String, BurrowError> {
    let payload = serde_json::to_string(&IceCandidatePayload {
        candidate,
        sdp_mid,
        sdp_m_line_index,
    })
    .map_err(|e| BurrowError::from(e.to_string()))?;

    build_gift_wrapped_signaling(
        KIND_ICE_CANDIDATE,
        &payload,
        &remote_pubkey_hex,
        &call_id,
        None,
    )
    .await
}

/// End an active call (kind 25053).
///
/// `call_id`: Call identifier.
/// `remote_pubkey_hex`: Hex-encoded public key of the remote peer.
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059).
#[frb]
pub async fn end_call(
    call_id: String,
    remote_pubkey_hex: String,
) -> Result<String, BurrowError> {
    build_gift_wrapped_signaling(
        KIND_CALL_END,
        "hangup",
        &remote_pubkey_hex,
        &call_id,
        None,
    )
    .await
}

/// Send a call state update (mute/camera toggle, kind 25054).
///
/// `call_id`: Call identifier.
/// `remote_pubkey_hex`: Hex-encoded public key of the remote peer.
/// `is_muted`: Current mute state, or None if unchanged.
/// `is_video_enabled`: Current video state, or None if unchanged.
///
/// Returns JSON-serialized gift-wrapped Event (kind 1059).
#[frb]
pub async fn send_call_state_update(
    call_id: String,
    remote_pubkey_hex: String,
    is_muted: Option<bool>,
    is_video_enabled: Option<bool>,
) -> Result<String, BurrowError> {
    let payload = serde_json::to_string(&CallStateUpdatePayload {
        is_muted,
        is_video_enabled,
    })
    .map_err(|e| BurrowError::from(e.to_string()))?;

    build_gift_wrapped_signaling(
        KIND_CALL_STATE_UPDATE,
        &payload,
        &remote_pubkey_hex,
        &call_id,
        None,
    )
    .await
}

/// Build a Nostr filter for subscribing to incoming call signaling events.
///
/// Subscribes to gift-wrapped events (kind 1059) addressed to the local user.
/// The client must unwrap received events and call `process_call_event()` on the inner event.
///
/// Returns JSON-serialized Filter.
#[frb]
pub async fn subscribe_call_events() -> Result<String, BurrowError> {
    state::with_state(|s| {
        let filter = Filter::new()
            .kind(Kind::GiftWrap)
            .pubkey(s.keys.public_key())
            .since(Timestamp::now());

        serde_json::to_string(&filter).map_err(|e| BurrowError::from(e.to_string()))
    })
    .await
}

/// Process an unwrapped call signaling event and return structured data.
///
/// After receiving a gift-wrapped event (kind 1059) and unwrapping it via NIP-59,
/// pass the inner rumor event JSON here to parse it into a `CallSignalingEvent`.
///
/// `event_json`: JSON-serialized inner event (kind 25050-25054).
///
/// Returns `None` if the event is not a call signaling event.
#[frb]
pub async fn process_call_event(
    event_json: String,
) -> Result<Option<CallSignalingEvent>, BurrowError> {
    let event: Event =
        Event::from_json(&event_json).map_err(|e| BurrowError::from(e.to_string()))?;

    let kind_num = event.kind.as_u16();

    // Only handle call signaling kinds
    if kind_num < KIND_CALL_OFFER || kind_num > KIND_CALL_STATE_UPDATE {
        return Ok(None);
    }

    // Extract call-id from tags
    let call_id = event
        .tags
        .iter()
        .find(|t| {
            t.as_slice()
                .first()
                .map(|v| v == "call-id")
                .unwrap_or(false)
        })
        .and_then(|t| t.as_slice().get(1).cloned())
        .unwrap_or_default();

    // Extract call-type from tags
    let call_type = event
        .tags
        .iter()
        .find(|t| {
            t.as_slice()
                .first()
                .map(|v| v == "call-type")
                .unwrap_or(false)
        })
        .and_then(|t| t.as_slice().get(1).cloned());

    Ok(Some(CallSignalingEvent {
        kind: kind_num as u32,
        sender_pubkey_hex: event.pubkey.to_hex(),
        call_id,
        call_type,
        content: event.content.to_string(),
        created_at: event.created_at.as_secs(),
    }))
}

/// Subscribe to incoming gift-wrapped events and stream unwrapped call signaling events.
///
/// This subscribes to kind 1059 (GiftWrap) events addressed to the local user,
/// unwraps them using NIP-59, and pushes any call signaling events (kinds 25050-25054)
/// to the provided stream sink.
///
/// Runs indefinitely until the stream is closed from the Dart side.
#[frb]
pub async fn listen_for_call_events(
    sink: StreamSink<CallSignalingEvent>,
) -> Result<(), BurrowError> {
    let (client, keys) = state::with_state(|s| Ok((s.client.clone(), s.keys.clone()))).await?;

    // Subscribe to gift-wrapped events addressed to us
    let filter = Filter::new()
        .kind(Kind::GiftWrap)
        .pubkey(keys.public_key())
        .since(Timestamp::now());

    client
        .subscribe(filter, None)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    // Listen for notifications
    client
        .handle_notifications(|notification| {
            let sink = &sink;
            let _keys = &keys;
            let client = &client;
            async move {
                if let nostr_sdk::RelayPoolNotification::Event { event, .. } = notification {
                    // Only process gift wraps
                    if event.kind == Kind::GiftWrap {
                        // Unwrap the gift wrap
                        match client.unwrap_gift_wrap(&event).await {
                            Ok(unwrapped) => {
                                let rumor = unwrapped.rumor;
                                let kind_num = rumor.kind.as_u16();

                                // Only forward call signaling kinds
                                if kind_num >= KIND_CALL_OFFER
                                    && kind_num <= KIND_CALL_STATE_UPDATE
                                {
                                    // Discard expired events (60s TTL)
                                    let expiration = rumor
                                        .tags
                                        .iter()
                                        .find(|t| {
                                            t.as_slice()
                                                .first()
                                                .map(|v| v == "expiration")
                                                .unwrap_or(false)
                                        })
                                        .and_then(|t| t.as_slice().get(1)?.parse::<u64>().ok());
                                    if let Some(exp) = expiration {
                                        if Timestamp::now().as_secs() > exp {
                                            return Ok(false);
                                        }
                                    }
                                    let call_id = rumor
                                        .tags
                                        .iter()
                                        .find(|t| {
                                            t.as_slice()
                                                .first()
                                                .map(|v| v == "call-id")
                                                .unwrap_or(false)
                                        })
                                        .and_then(|t| t.as_slice().get(1).cloned())
                                        .unwrap_or_default();

                                    let call_type = rumor
                                        .tags
                                        .iter()
                                        .find(|t| {
                                            t.as_slice()
                                                .first()
                                                .map(|v| v == "call-type")
                                                .unwrap_or(false)
                                        })
                                        .and_then(|t| t.as_slice().get(1).cloned());

                                    let event = CallSignalingEvent {
                                        kind: kind_num as u32,
                                        sender_pubkey_hex: unwrapped.sender.to_hex(),
                                        call_id,
                                        call_type,
                                        content: rumor.content.to_string(),
                                        created_at: rumor.created_at.as_secs(),
                                    };

                                    let _ = sink.add(event);
                                }
                            }
                            Err(_) => {
                                // Could not unwrap — not for us or corrupted
                            }
                        }
                    }
                }
                Ok(false) // false = keep listening
            }
        })
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    Ok(())
}

/// Build a call signaling event for a group call (MLS-encrypted, not gift-wrapped).
///
/// For group calls, signaling goes through the Marmot group message channel.
/// This creates a rumor event that should be passed to `send_message()` for MLS encryption.
///
/// `kind_num`: Event kind (25050-25054).
/// `content`: JSON payload (SDP, ICE candidate, etc.).
/// `call_id`: Call identifier.
/// `call_type`: Optional call type ("audio" or "video").
///
/// Returns JSON-serialized unsigned rumor event to be encrypted via `send_message()`.
#[frb]
pub async fn build_group_call_signaling(
    kind_num: u32,
    content: String,
    call_id: String,
    call_type: Option<String>,
) -> Result<String, BurrowError> {
    state::with_state(|s| {
        let mut tags = vec![Tag::custom(
            TagKind::custom("call-id"),
            vec![call_id],
        )];

        if let Some(ct) = call_type {
            tags.push(Tag::custom(
                TagKind::custom("call-type"),
                vec![ct],
            ));
        }

        let event = EventBuilder::new(Kind::from(kind_num as u16), &content)
            .tags(tags)
            .build(s.keys.public_key());

        serde_json::to_string(&event).map_err(|e| BurrowError::from(e.to_string()))
    })
    .await
}
