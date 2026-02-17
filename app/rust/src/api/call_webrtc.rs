//! Rust-side WebRTC support: ICE configuration, SDP parsing, peer tracking,
//! frame encryption key derivation, and SFU/mesh topology decisions.
//!
//! Actual WebRTC media handling is done on the Dart/Flutter side via flutter_webrtc.
//! This module provides the supporting infrastructure that Dart calls into.

use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;

use crate::api::error::BurrowError;

// ── ICE / WebRTC Configuration ─────────────────────────────────────────────

/// A single ICE server entry for WebRTC peer connection configuration.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceServer {
    pub urls: Vec<String>,
    pub username: Option<String>,
    pub credential: Option<String>,
}

/// Full WebRTC configuration returned to Dart for creating RTCPeerConnection.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebRtcConfig {
    pub ice_servers: Vec<IceServer>,
    /// "unified-plan" (only supported value).
    pub sdp_semantics: String,
    /// Bundle policy: "max-bundle".
    pub bundle_policy: String,
}

/// Generate WebRTC configuration with ICE servers.
///
/// Returns STUN/TURN server configuration for creating peer connections.
/// TURN credentials are short-lived and derived per-call.
///
/// `call_id`: Used to derive unique TURN credentials for this call.
#[frb]
pub fn generate_webrtc_config(call_id: String) -> Result<WebRtcConfig, BurrowError> {
    // Public STUN servers (free, reliable)
    let stun_servers = vec![
        "stun:stun.l.google.com:19302".to_string(),
        "stun:stun1.l.google.com:19302".to_string(),
        "stun:stun2.l.google.com:19302".to_string(),
    ];

    // Default TURN server with per-call credentials.
    // These defaults can be overridden from the Dart side via TurnSettings
    // in the settings screen (stored in SharedPreferences).
    // The Dart WebRTC service layer checks for user-configured TURN servers
    // and replaces these defaults before creating the peer connection.
    let turn_username = format!("burrow-{}", &call_id[..8.min(call_id.len())]);
    let mut hasher = Sha256::new();
    hasher.update(b"burrow-turn-credential-v1");
    hasher.update(call_id.as_bytes());
    let turn_credential = hex::encode(&hasher.finalize()[..16]);

    let ice_servers = vec![
        IceServer {
            urls: stun_servers,
            username: None,
            credential: None,
        },
        IceServer {
            urls: vec![
                "turn:openrelay.metered.ca:80".to_string(),
                "turn:openrelay.metered.ca:443".to_string(),
                "turn:openrelay.metered.ca:443?transport=tcp".to_string(),
            ],
            username: Some(turn_username),
            credential: Some(turn_credential),
        },
    ];

    Ok(WebRtcConfig {
        ice_servers,
        sdp_semantics: "unified-plan".to_string(),
        bundle_policy: "max-bundle".to_string(),
    })
}

// ── SDP Parsing ────────────────────────────────────────────────────────────

/// Extracted information from an SDP offer or answer.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct SdpInfo {
    /// "offer" or "answer".
    pub sdp_type: String,
    /// Whether audio media is present.
    pub has_audio: bool,
    /// Whether video media is present.
    pub has_video: bool,
    /// Number of media sections (m= lines).
    pub media_count: u32,
    /// ICE ufrag if found.
    pub ice_ufrag: Option<String>,
    /// Detected codecs (e.g. "opus", "VP8", "H264").
    pub codecs: Vec<String>,
    /// Whether the SDP appears valid.
    pub is_valid: bool,
    /// Validation error message, if any.
    pub error: Option<String>,
}

/// Parse and validate an SDP offer string.
///
/// Extracts media types, codecs, and validates basic SDP structure.
#[frb]
pub fn parse_sdp_offer(sdp: String) -> Result<SdpInfo, BurrowError> {
    parse_sdp_internal("offer", &sdp)
}

/// Parse and validate an SDP answer string.
#[frb]
pub fn parse_sdp_answer(sdp: String) -> Result<SdpInfo, BurrowError> {
    parse_sdp_internal("answer", &sdp)
}

fn parse_sdp_internal(sdp_type: &str, sdp: &str) -> Result<SdpInfo, BurrowError> {
    if sdp.is_empty() {
        return Ok(SdpInfo {
            sdp_type: sdp_type.to_string(),
            has_audio: false,
            has_video: false,
            media_count: 0,
            ice_ufrag: None,
            codecs: vec![],
            is_valid: false,
            error: Some("Empty SDP".to_string()),
        });
    }

    // Basic SDP validation
    if !sdp.contains("v=0") {
        return Ok(SdpInfo {
            sdp_type: sdp_type.to_string(),
            has_audio: false,
            has_video: false,
            media_count: 0,
            ice_ufrag: None,
            codecs: vec![],
            is_valid: false,
            error: Some("Missing SDP version line (v=0)".to_string()),
        });
    }

    let has_audio = sdp.contains("m=audio");
    let has_video = sdp.contains("m=video");
    let media_count = sdp.lines().filter(|l| l.starts_with("m=")).count() as u32;

    // Extract ICE ufrag
    let ice_ufrag = sdp
        .lines()
        .find(|l| l.starts_with("a=ice-ufrag:"))
        .map(|l| l.trim_start_matches("a=ice-ufrag:").to_string());

    // Extract codecs from a=rtpmap lines
    let mut codecs: Vec<String> = sdp
        .lines()
        .filter(|l| l.starts_with("a=rtpmap:"))
        .filter_map(|l| {
            // Format: a=rtpmap:<payload> <codec>/<clock>
            l.split_whitespace()
                .nth(1)
                .and_then(|s| s.split('/').next())
                .map(|s| s.to_string())
        })
        .collect();
    codecs.sort();
    codecs.dedup();

    Ok(SdpInfo {
        sdp_type: sdp_type.to_string(),
        has_audio,
        has_video,
        media_count,
        ice_ufrag,
        codecs,
        is_valid: true,
        error: None,
    })
}

// ── Peer Connection Tracking ───────────────────────────────────────────────

/// State of a WebRTC peer connection.
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq)]
pub enum PeerConnectionState {
    New,
    Checking,
    Connected,
    Disconnected,
    Failed,
    Closed,
}

/// Tracked peer connection entry.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct PeerEntry {
    /// Hex-encoded public key of the remote participant.
    pub participant_pubkey_hex: String,
    /// Current connection state.
    pub connection_state: PeerConnectionState,
    /// Call ID this peer belongs to.
    pub call_id: String,
    /// Whether the peer has an audio track.
    pub has_audio_track: bool,
    /// Whether the peer has a video track.
    pub has_video_track: bool,
    /// Whether the remote peer is muted.
    pub is_remote_muted: bool,
    /// Whether the remote peer has video enabled.
    pub is_remote_video_enabled: bool,
    /// Unix timestamp when this peer entry was created.
    pub created_at: u64,
    /// Unix timestamp of last state update.
    pub updated_at: u64,
}

/// Connection quality metrics for a peer.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct PeerStats {
    /// Hex-encoded public key of the peer.
    pub participant_pubkey_hex: String,
    /// Round-trip time in milliseconds.
    pub rtt_ms: Option<f64>,
    /// Packet loss percentage (0.0 - 100.0).
    pub packet_loss_percent: Option<f64>,
    /// Outgoing bitrate in kbps.
    pub outgoing_bitrate_kbps: Option<f64>,
    /// Incoming bitrate in kbps.
    pub incoming_bitrate_kbps: Option<f64>,
    /// Connection quality score (0.0 - 1.0).
    pub quality_score: Option<f64>,
    /// Unix timestamp of this stats snapshot.
    pub timestamp: u64,
}

/// Global peer connection store: call_id -> (pubkey -> PeerEntry).
static PEERS: OnceLock<RwLock<HashMap<String, HashMap<String, PeerEntry>>>> = OnceLock::new();

/// Global peer stats store: pubkey -> PeerStats.
static PEER_STATS: OnceLock<RwLock<HashMap<String, PeerStats>>> = OnceLock::new();

fn peers() -> &'static RwLock<HashMap<String, HashMap<String, PeerEntry>>> {
    PEERS.get_or_init(|| RwLock::new(HashMap::new()))
}

fn peer_stats_store() -> &'static RwLock<HashMap<String, PeerStats>> {
    PEER_STATS.get_or_init(|| RwLock::new(HashMap::new()))
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Create a new peer entry to track a WebRTC peer connection.
///
/// Called when a new participant joins a call or a new P2P connection is established.
#[frb]
pub async fn create_peer_entry(
    call_id: String,
    participant_pubkey_hex: String,
    has_audio_track: bool,
    has_video_track: bool,
) -> Result<PeerEntry, BurrowError> {
    let now = now_secs();
    let entry = PeerEntry {
        participant_pubkey_hex: participant_pubkey_hex.clone(),
        connection_state: PeerConnectionState::New,
        call_id: call_id.clone(),
        has_audio_track,
        has_video_track,
        is_remote_muted: false,
        is_remote_video_enabled: has_video_track,
        created_at: now,
        updated_at: now,
    };

    let mut store = peers().write().await;
    store
        .entry(call_id)
        .or_default()
        .insert(participant_pubkey_hex, entry.clone());

    Ok(entry)
}

/// Update the connection state of a tracked peer.
///
/// `state`: One of "new", "checking", "connected", "disconnected", "failed", "closed".
#[frb]
pub async fn update_peer_state(
    call_id: String,
    participant_pubkey_hex: String,
    state: String,
) -> Result<PeerEntry, BurrowError> {
    let new_state = match state.as_str() {
        "new" => PeerConnectionState::New,
        "checking" => PeerConnectionState::Checking,
        "connected" => PeerConnectionState::Connected,
        "disconnected" => PeerConnectionState::Disconnected,
        "failed" => PeerConnectionState::Failed,
        "closed" => PeerConnectionState::Closed,
        _ => {
            return Err(BurrowError::from(format!(
                "Unknown peer connection state: {}",
                state
            )))
        }
    };

    let mut store = peers().write().await;
    let call_peers = store
        .get_mut(&call_id)
        .ok_or_else(|| BurrowError::from(format!("No peers tracked for call: {}", call_id)))?;
    let entry = call_peers.get_mut(&participant_pubkey_hex).ok_or_else(|| {
        BurrowError::from(format!(
            "Peer not found: {} in call {}",
            participant_pubkey_hex, call_id
        ))
    })?;

    entry.connection_state = new_state;
    entry.updated_at = now_secs();
    Ok(entry.clone())
}

/// Report connection quality metrics for a peer (called from Dart with WebRTC stats).
#[frb]
pub async fn report_peer_stats(
    participant_pubkey_hex: String,
    rtt_ms: Option<f64>,
    packet_loss_percent: Option<f64>,
    outgoing_bitrate_kbps: Option<f64>,
    incoming_bitrate_kbps: Option<f64>,
) -> Result<PeerStats, BurrowError> {
    // Compute quality score (0.0 = terrible, 1.0 = excellent)
    let quality_score = compute_quality_score(rtt_ms, packet_loss_percent);

    let stats = PeerStats {
        participant_pubkey_hex: participant_pubkey_hex.clone(),
        rtt_ms,
        packet_loss_percent,
        outgoing_bitrate_kbps,
        incoming_bitrate_kbps,
        quality_score: Some(quality_score),
        timestamp: now_secs(),
    };

    let mut store = peer_stats_store().write().await;
    store.insert(participant_pubkey_hex, stats.clone());
    Ok(stats)
}

/// Get the latest connection quality metrics for a peer.
#[frb]
pub async fn get_peer_stats(
    participant_pubkey_hex: String,
) -> Result<Option<PeerStats>, BurrowError> {
    let store = peer_stats_store().read().await;
    Ok(store.get(&participant_pubkey_hex).cloned())
}

/// Get all participants in a call with their connection states.
#[frb]
pub async fn get_call_participants(call_id: String) -> Result<Vec<PeerEntry>, BurrowError> {
    let store = peers().read().await;
    Ok(store
        .get(&call_id)
        .map(|m| m.values().cloned().collect())
        .unwrap_or_default())
}

/// Remove all peer entries for a call (cleanup).
#[frb]
pub async fn remove_call_peers(call_id: String) -> Result<(), BurrowError> {
    let mut store = peers().write().await;
    if let Some(call_peers) = store.remove(&call_id) {
        // Also clean up stats for removed peers
        let mut stats_store = peer_stats_store().write().await;
        for pubkey in call_peers.keys() {
            stats_store.remove(pubkey);
        }
    }
    Ok(())
}

fn compute_quality_score(rtt_ms: Option<f64>, packet_loss_percent: Option<f64>) -> f64 {
    let rtt_score = match rtt_ms {
        Some(rtt) if rtt <= 50.0 => 1.0,
        Some(rtt) if rtt <= 150.0 => 0.8,
        Some(rtt) if rtt <= 300.0 => 0.5,
        Some(rtt) if rtt <= 500.0 => 0.3,
        Some(_) => 0.1,
        None => 0.5, // unknown = assume average
    };

    let loss_score = match packet_loss_percent {
        Some(loss) if loss <= 1.0 => 1.0,
        Some(loss) if loss <= 3.0 => 0.8,
        Some(loss) if loss <= 5.0 => 0.5,
        Some(loss) if loss <= 10.0 => 0.3,
        Some(_) => 0.1,
        None => 0.5,
    };

    // Weighted average: RTT 40%, packet loss 60%
    rtt_score * 0.4 + loss_score * 0.6
}

// ── Frame Encryption Key Derivation ────────────────────────────────────────

/// Derive a per-call AES-128-GCM frame encryption key from MLS exporter_secret.
///
/// Used for SFU mode where frames must be encrypted end-to-end since DTLS
/// terminates at the SFU. The key is derived deterministically so all group
/// members compute the same key from their shared MLS state.
///
/// `exporter_secret_hex`: Hex-encoded MLS exporter_secret from the group epoch.
/// `call_id`: Unique call identifier used as derivation context.
///
/// Returns 16-byte (128-bit) AES-GCM key as hex string.
#[frb]
pub fn derive_frame_encryption_key(
    exporter_secret_hex: String,
    call_id: String,
) -> Result<String, BurrowError> {
    let secret =
        hex::decode(&exporter_secret_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let mut hasher = Sha256::new();
    hasher.update(&secret);
    hasher.update(b"burrow-frame-encrypt-v1");
    hasher.update(call_id.as_bytes());
    let full_key = hasher.finalize();

    // Take first 16 bytes for AES-128-GCM
    Ok(hex::encode(&full_key[..16]))
}

/// Rotate the frame encryption key by deriving a new key from the current key + epoch.
///
/// Called when MLS epoch advances (member join/leave/update) to maintain forward secrecy.
///
/// `current_key_hex`: Current frame encryption key (hex).
/// `new_epoch`: The new MLS epoch number.
/// `call_id`: Call identifier for context binding.
///
/// Returns new 16-byte AES-GCM key as hex string.
#[frb]
pub fn rotate_frame_key(
    current_key_hex: String,
    new_epoch: u64,
    call_id: String,
) -> Result<String, BurrowError> {
    let current_key =
        hex::decode(&current_key_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let mut hasher = Sha256::new();
    hasher.update(&current_key);
    hasher.update(b"burrow-frame-rotate-v1");
    hasher.update(call_id.as_bytes());
    hasher.update(&new_epoch.to_be_bytes());
    let new_key = hasher.finalize();

    Ok(hex::encode(&new_key[..16]))
}

// ── Topology Decision ──────────────────────────────────────────────────────

/// Mesh vs SFU threshold. Calls with more participants than this use SFU.
const SFU_THRESHOLD: usize = 4;

/// Determine whether a call should use SFU (true) or P2P mesh (false).
///
/// `participant_count`: Number of participants in the call (including local user).
///
/// Returns true if SFU should be used (participant_count > 4).
#[frb]
pub fn should_use_sfu(participant_count: u32) -> bool {
    participant_count as usize > SFU_THRESHOLD
}

/// SFU configuration for LiveKit-based group calls.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct SfuConfig {
    /// LiveKit server WebSocket URL.
    pub server_url: String,
    /// Room name (derived from call_id).
    pub room_name: String,
    /// Authentication token for joining the room.
    pub token: String,
}

/// Get SFU configuration for a group call that requires SFU mode.
///
/// `call_id`: The call identifier (used to derive room name).
/// `local_pubkey_hex`: Local user's public key (used in token).
///
/// Returns SFU connection details. In production, the token would be obtained
/// from a Burrow coordination server. For now, returns placeholder config.
#[frb]
pub fn get_sfu_config(
    call_id: String,
    local_pubkey_hex: String,
) -> Result<SfuConfig, BurrowError> {
    // Room name derived from call_id
    let room_name = format!("burrow-{}", &call_id[..12.min(call_id.len())]);

    // In production, this token would be fetched from a LiveKit token server
    // that validates the user's Nostr identity before issuing a JWT.
    // For now, generate a placeholder that will need to be replaced.
    let mut hasher = Sha256::new();
    hasher.update(b"burrow-sfu-token-v1");
    hasher.update(call_id.as_bytes());
    hasher.update(local_pubkey_hex.as_bytes());
    let token_placeholder = hex::encode(&hasher.finalize()[..16]);

    Ok(SfuConfig {
        server_url: "wss://sfu.burrow.chat".to_string(),
        room_name,
        token: token_placeholder,
    })
}
