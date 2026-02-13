//! Call session state machine and session management.
//!
//! Manages call lifecycle from initiation to termination, tracks active calls,
//! and derives media encryption keys from MLS exporter secrets.

use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

use flutter_rust_bridge::frb;
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;

use crate::api::error::BurrowError;

/// Call state machine states.
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq)]
pub enum CallState {
    /// No active call.
    Idle,
    /// Outgoing call initiated, waiting for remote answer.
    Initiating,
    /// Incoming call ringing, waiting for local user to accept/reject.
    Ringing,
    /// Signaling complete, ICE/DTLS negotiation in progress.
    Connecting,
    /// Media flowing, call is active.
    Active,
    /// Call is ending (hangup sent, waiting for cleanup).
    Ending,
    /// Call failed (ICE failure, timeout, etc.).
    Failed,
    /// Call was rejected by the remote party.
    Rejected,
}

/// Type of call media.
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq)]
pub enum CallType {
    Audio,
    Video,
}

/// Direction of the call relative to local user.
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq)]
pub enum CallDirection {
    Outgoing,
    Incoming,
}

/// A call session tracking all state for one call.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct CallSession {
    /// Unique identifier for this call (UUIDv4 string).
    pub call_id: String,
    /// Current state of the call.
    pub state: CallState,
    /// Type of call (audio or video).
    pub call_type: CallType,
    /// Direction (incoming or outgoing).
    pub direction: CallDirection,
    /// Hex-encoded public keys of all participants.
    pub participants: Vec<String>,
    /// Hex-encoded local user public key.
    pub local_pubkey_hex: String,
    /// Hex-encoded remote user public key (1:1 calls).
    pub remote_pubkey_hex: String,
    /// Optional hex-encoded MLS group ID (for group calls).
    pub group_id_hex: Option<String>,
    /// Unix timestamp when session was created.
    pub created_at: u64,
    /// Unix timestamp when call became active (media flowing).
    pub started_at: Option<u64>,
    /// Unix timestamp when call ended.
    pub ended_at: Option<u64>,
    /// Whether local audio is muted.
    pub is_muted: bool,
    /// Whether local video is enabled.
    pub is_video_enabled: bool,
}

/// Global call session store.
static SESSIONS: OnceLock<RwLock<HashMap<String, CallSession>>> = OnceLock::new();

fn sessions() -> &'static RwLock<HashMap<String, CallSession>> {
    SESSIONS.get_or_init(|| RwLock::new(HashMap::new()))
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Create a new call session.
///
/// `call_id`: Unique call identifier (UUIDv4).
/// `call_type`: "audio" or "video".
/// `direction`: "outgoing" or "incoming".
/// `local_pubkey_hex`: Local user's hex-encoded public key.
/// `remote_pubkey_hex`: Remote user's hex-encoded public key.
/// `group_id_hex`: Optional MLS group ID for group calls.
#[frb]
pub async fn create_session(
    call_id: String,
    call_type: String,
    direction: String,
    local_pubkey_hex: String,
    remote_pubkey_hex: String,
    group_id_hex: Option<String>,
) -> Result<CallSession, BurrowError> {
    let ct = match call_type.as_str() {
        "video" => CallType::Video,
        _ => CallType::Audio,
    };
    let dir = match direction.as_str() {
        "incoming" => CallDirection::Incoming,
        _ => CallDirection::Outgoing,
    };
    let initial_state = match dir {
        CallDirection::Outgoing => CallState::Initiating,
        CallDirection::Incoming => CallState::Ringing,
    };

    let session = CallSession {
        call_id: call_id.clone(),
        state: initial_state,
        call_type: ct,
        direction: dir,
        participants: vec![local_pubkey_hex.clone(), remote_pubkey_hex.clone()],
        local_pubkey_hex,
        remote_pubkey_hex,
        group_id_hex,
        created_at: now_secs(),
        started_at: None,
        ended_at: None,
        is_muted: false,
        is_video_enabled: call_type == "video",
    };

    let mut store = sessions().write().await;
    store.insert(call_id, session.clone());
    Ok(session)
}

/// Update the state of an existing call session.
///
/// `state`: One of "idle", "initiating", "ringing", "connecting", "active", "ending", "failed", "rejected".
#[frb]
pub async fn update_session_state(
    call_id: String,
    state: String,
) -> Result<CallSession, BurrowError> {
    let new_state = match state.as_str() {
        "idle" => CallState::Idle,
        "initiating" => CallState::Initiating,
        "ringing" => CallState::Ringing,
        "connecting" => CallState::Connecting,
        "active" => CallState::Active,
        "ending" => CallState::Ending,
        "failed" => CallState::Failed,
        "rejected" => CallState::Rejected,
        _ => return Err(BurrowError::from(format!("Unknown call state: {}", state))),
    };

    let mut store = sessions().write().await;
    let session = store
        .get_mut(&call_id)
        .ok_or_else(|| BurrowError::from(format!("Call session not found: {}", call_id)))?;

    session.state = new_state.clone();

    // Track timing milestones
    match new_state {
        CallState::Active => {
            if session.started_at.is_none() {
                session.started_at = Some(now_secs());
            }
        }
        CallState::Ending | CallState::Failed | CallState::Rejected | CallState::Idle => {
            if session.ended_at.is_none() {
                session.ended_at = Some(now_secs());
            }
        }
        _ => {}
    }

    Ok(session.clone())
}

/// Get a call session by its ID.
#[frb]
pub async fn get_session(call_id: String) -> Result<Option<CallSession>, BurrowError> {
    let store = sessions().read().await;
    Ok(store.get(&call_id).cloned())
}

/// Get all active call sessions (state is not Idle, Failed, Rejected, or Ending with ended_at set).
#[frb]
pub async fn get_active_calls() -> Result<Vec<CallSession>, BurrowError> {
    let store = sessions().read().await;
    Ok(store
        .values()
        .filter(|s| {
            matches!(
                s.state,
                CallState::Initiating
                    | CallState::Ringing
                    | CallState::Connecting
                    | CallState::Active
                    | CallState::Ending
            )
        })
        .cloned()
        .collect())
}

/// Remove a call session from the store (cleanup after call ends).
#[frb]
pub async fn remove_session(call_id: String) -> Result<(), BurrowError> {
    let mut store = sessions().write().await;
    store.remove(&call_id);
    Ok(())
}

/// Update local mute state for a call session.
#[frb]
pub async fn set_muted(call_id: String, muted: bool) -> Result<CallSession, BurrowError> {
    let mut store = sessions().write().await;
    let session = store
        .get_mut(&call_id)
        .ok_or_else(|| BurrowError::from(format!("Call session not found: {}", call_id)))?;
    session.is_muted = muted;
    Ok(session.clone())
}

/// Update local video enabled state for a call session.
#[frb]
pub async fn set_video_enabled(
    call_id: String,
    enabled: bool,
) -> Result<CallSession, BurrowError> {
    let mut store = sessions().write().await;
    let session = store
        .get_mut(&call_id)
        .ok_or_else(|| BurrowError::from(format!("Call session not found: {}", call_id)))?;
    session.is_video_enabled = enabled;
    Ok(session.clone())
}

/// Derive a media encryption key from MLS exporter_secret for SFU frame encryption.
///
/// Uses HKDF-like derivation: SHA-256(exporter_secret || "burrow-media-v1" || call_id).
/// Returns 32-byte key as hex string.
///
/// `exporter_secret_hex`: Hex-encoded MLS exporter_secret from the group.
/// `call_id`: Unique call identifier used as context.
#[frb]
pub fn derive_media_key(
    exporter_secret_hex: String,
    call_id: String,
) -> Result<String, BurrowError> {
    let secret =
        hex::decode(&exporter_secret_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let mut hasher = Sha256::new();
    hasher.update(&secret);
    hasher.update(b"burrow-media-v1");
    hasher.update(call_id.as_bytes());
    let key = hasher.finalize();

    Ok(hex::encode(key))
}
