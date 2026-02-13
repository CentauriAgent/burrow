//! Tests for call signaling, session management, WebRTC support, and quality modules.

use rust_lib_burrow_app::api::call_session::*;
use rust_lib_burrow_app::api::call_webrtc::*;
use rust_lib_burrow_app::api::call_quality::*;

// ── Call Session Tests ─────────────────────────────────────────────────────

#[tokio::test]
async fn test_create_session_outgoing() {
    let session = create_session(
        "call-001".into(),
        "audio".into(),
        "outgoing".into(),
        "aabb".into(),
        "ccdd".into(),
        None,
    )
    .await
    .unwrap();

    assert_eq!(session.call_id, "call-001");
    assert_eq!(session.state, CallState::Initiating);
    assert_eq!(session.call_type, CallType::Audio);
    assert_eq!(session.direction, CallDirection::Outgoing);
    assert_eq!(session.local_pubkey_hex, "aabb");
    assert_eq!(session.remote_pubkey_hex, "ccdd");
    assert!(session.started_at.is_none());
    assert!(!session.is_muted);
}

#[tokio::test]
async fn test_create_session_incoming() {
    let session = create_session(
        "call-002".into(),
        "video".into(),
        "incoming".into(),
        "1111".into(),
        "2222".into(),
        None,
    )
    .await
    .unwrap();

    assert_eq!(session.state, CallState::Ringing);
    assert_eq!(session.call_type, CallType::Video);
    assert_eq!(session.direction, CallDirection::Incoming);
    assert!(session.is_video_enabled);
}

#[tokio::test]
async fn test_session_state_transitions() {
    let call_id = "call-transitions-001".to_string();
    create_session(
        call_id.clone(),
        "audio".into(),
        "outgoing".into(),
        "aa".into(),
        "bb".into(),
        None,
    )
    .await
    .unwrap();

    let s = update_session_state(call_id.clone(), "connecting".into())
        .await
        .unwrap();
    assert_eq!(s.state, CallState::Connecting);

    let s = update_session_state(call_id.clone(), "active".into())
        .await
        .unwrap();
    assert_eq!(s.state, CallState::Active);
    assert!(s.started_at.is_some());

    let s = update_session_state(call_id.clone(), "ending".into())
        .await
        .unwrap();
    assert_eq!(s.state, CallState::Ending);
    assert!(s.ended_at.is_some());

    // Cleanup
    remove_session(call_id).await.unwrap();
}

#[tokio::test]
async fn test_get_active_calls() {
    let id1 = "active-test-1".to_string();
    let id2 = "active-test-2".to_string();

    create_session(id1.clone(), "audio".into(), "outgoing".into(), "a".into(), "b".into(), None)
        .await
        .unwrap();
    create_session(id2.clone(), "video".into(), "incoming".into(), "c".into(), "d".into(), None)
        .await
        .unwrap();

    let active = get_active_calls().await.unwrap();
    assert!(active.len() >= 2);

    // Cleanup
    remove_session(id1).await.unwrap();
    remove_session(id2).await.unwrap();
}

#[tokio::test]
async fn test_mute_and_video_toggle() {
    let call_id = "mute-test-001".to_string();
    create_session(call_id.clone(), "video".into(), "outgoing".into(), "a".into(), "b".into(), None)
        .await
        .unwrap();

    let s = set_muted(call_id.clone(), true).await.unwrap();
    assert!(s.is_muted);

    let s = set_video_enabled(call_id.clone(), false).await.unwrap();
    assert!(!s.is_video_enabled);

    remove_session(call_id).await.unwrap();
}

#[tokio::test]
async fn test_derive_media_key() {
    let key = derive_media_key(
        "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789".into(),
        "call-key-test".into(),
    )
    .unwrap();

    assert_eq!(key.len(), 64); // 32 bytes = 64 hex chars
    assert!(key.chars().all(|c| c.is_ascii_hexdigit()));
}

#[tokio::test]
async fn test_derive_media_key_deterministic() {
    let secret = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233";
    let call_id = "deterministic-test";

    let key1 = derive_media_key(secret.into(), call_id.into()).unwrap();
    let key2 = derive_media_key(secret.into(), call_id.into()).unwrap();
    assert_eq!(key1, key2);
}

// ── WebRTC Config Tests ────────────────────────────────────────────────────

#[test]
fn test_generate_webrtc_config() {
    let config = generate_webrtc_config("test-call-id".into()).unwrap();

    assert_eq!(config.sdp_semantics, "unified-plan");
    assert_eq!(config.bundle_policy, "max-bundle");
    assert!(config.ice_servers.len() >= 2); // STUN + TURN
    assert!(config.ice_servers[0].urls[0].starts_with("stun:"));
    assert!(config.ice_servers[1].urls[0].starts_with("turn:"));
    assert!(config.ice_servers[1].username.is_some());
    assert!(config.ice_servers[1].credential.is_some());
}

#[test]
fn test_webrtc_config_unique_turn_credentials() {
    let c1 = generate_webrtc_config("call-a".into()).unwrap();
    let c2 = generate_webrtc_config("call-b".into()).unwrap();

    assert_ne!(
        c1.ice_servers[1].credential,
        c2.ice_servers[1].credential
    );
}

// ── SDP Parsing Tests ──────────────────────────────────────────────────────

#[test]
fn test_parse_sdp_offer_valid() {
    let sdp = "v=0\r\no=- 123 456 IN IP4 0.0.0.0\r\ns=-\r\nt=0 0\r\n\
               m=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\n\
               a=ice-ufrag:abc123\r\n\
               m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n";

    let info = parse_sdp_offer(sdp.into()).unwrap();
    assert!(info.is_valid);
    assert!(info.has_audio);
    assert!(info.has_video);
    assert_eq!(info.media_count, 2);
    assert_eq!(info.ice_ufrag, Some("abc123".to_string()));
    assert!(info.codecs.contains(&"opus".to_string()));
    assert!(info.codecs.contains(&"VP8".to_string()));
}

#[test]
fn test_parse_sdp_empty() {
    let info = parse_sdp_offer("".into()).unwrap();
    assert!(!info.is_valid);
    assert!(info.error.is_some());
}

#[test]
fn test_parse_sdp_no_version() {
    let info = parse_sdp_offer("m=audio 9\r\n".into()).unwrap();
    assert!(!info.is_valid);
}

// ── Peer Connection Tracking Tests ─────────────────────────────────────────

#[tokio::test]
async fn test_peer_lifecycle() {
    let call_id = "peer-lifecycle-001".to_string();
    let pubkey = "deadbeef".to_string();

    let entry = create_peer_entry(
        call_id.clone(),
        pubkey.clone(),
        true,
        true,
    )
    .await
    .unwrap();
    assert_eq!(entry.connection_state, PeerConnectionState::New);

    let entry = update_peer_state(call_id.clone(), pubkey.clone(), "connected".into())
        .await
        .unwrap();
    assert_eq!(entry.connection_state, PeerConnectionState::Connected);

    let participants = get_call_participants(call_id.clone()).await.unwrap();
    assert_eq!(participants.len(), 1);

    remove_call_peers(call_id).await.unwrap();
}

#[tokio::test]
async fn test_peer_stats() {
    let pubkey = "stats-peer-001".to_string();

    let stats = report_peer_stats(
        pubkey.clone(),
        Some(50.0),
        Some(1.0),
        Some(500.0),
        Some(450.0),
    )
    .await
    .unwrap();

    assert!(stats.quality_score.unwrap() > 0.5);

    let fetched = get_peer_stats(pubkey).await.unwrap();
    assert!(fetched.is_some());
}

// ── Frame Encryption Tests ─────────────────────────────────────────────────

#[test]
fn test_derive_frame_encryption_key() {
    let key = derive_frame_encryption_key(
        "0011223344556677889900aabbccddeeff0011223344556677889900aabbccddeeff".into(),
        "frame-key-test".into(),
    )
    .unwrap();

    assert_eq!(key.len(), 32); // 16 bytes = 32 hex chars
}

#[test]
fn test_rotate_frame_key() {
    let initial = derive_frame_encryption_key(
        "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789".into(),
        "rotate-test".into(),
    )
    .unwrap();

    let rotated = rotate_frame_key(initial.clone(), 2, "rotate-test".into()).unwrap();
    assert_ne!(initial, rotated);
    assert_eq!(rotated.len(), 32);

    // Same epoch produces same result
    let rotated2 = rotate_frame_key(initial, 2, "rotate-test".into()).unwrap();
    assert_eq!(rotated, rotated2);
}

// ── Topology Tests ─────────────────────────────────────────────────────────

#[test]
fn test_should_use_sfu() {
    assert!(!should_use_sfu(2));
    assert!(!should_use_sfu(4));
    assert!(should_use_sfu(5));
    assert!(should_use_sfu(10));
}

#[test]
fn test_get_sfu_config() {
    let config = get_sfu_config("abcdef123456".into(), "pubkey123".into()).unwrap();
    assert!(config.server_url.starts_with("wss://"));
    assert!(config.room_name.starts_with("burrow-"));
    assert!(!config.token.is_empty());
}

// ── Quality Score Tests ────────────────────────────────────────────────────

#[test]
fn test_quality_score_excellent() {
    let score = calculate_quality_score(30.0, 5.0, 0.3, 2000.0, true);
    assert!(score.score >= 0.85);
    assert_eq!(score.label, "excellent");
}

#[test]
fn test_quality_score_poor() {
    let score = calculate_quality_score(400.0, 80.0, 8.0, 80.0, true);
    assert!(score.score < 0.45);
}

#[test]
fn test_quality_score_audio_vs_video() {
    let audio = calculate_quality_score(50.0, 10.0, 1.0, 40.0, false);
    let video = calculate_quality_score(50.0, 10.0, 1.0, 40.0, true);
    // Audio at 40kbps is fine; video at 40kbps is not
    assert!(audio.bitrate_score > video.bitrate_score);
}

// ── Audio/Video Constraints Tests ──────────────────────────────────────────

#[test]
fn test_voice_audio_constraints() {
    let c = get_audio_constraints(AudioMode::Voice);
    assert_eq!(c.channel_count, 1);
    assert!(c.echo_cancellation);
    assert!(c.noise_suppression);
    assert!(c.dtx_enabled);
    assert!(c.fec_enabled);
}

#[test]
fn test_music_audio_constraints() {
    let c = get_audio_constraints(AudioMode::Music);
    assert_eq!(c.channel_count, 2);
    assert!(!c.echo_cancellation);
    assert!(!c.noise_suppression);
    assert!(!c.dtx_enabled);
}

#[test]
fn test_video_presets() {
    let low = get_video_constraints(VideoQualityPreset::Low);
    let hd = get_video_constraints(VideoQualityPreset::Hd);
    assert!(low.max_bitrate_bps < hd.max_bitrate_bps);
    assert!(low.width < hd.width);
    assert!(low.frame_rate <= hd.frame_rate);
}

#[test]
fn test_adaptive_bitrate_config() {
    let config = get_adaptive_bitrate_config();
    assert!(config.degradation_threshold_bps < config.recovery_threshold_bps);
    assert_eq!(config.quality_steps.len(), 4);
}

#[test]
fn test_simulcast_config() {
    let config = get_simulcast_config();
    assert!(config.enabled);
    assert_eq!(config.layers.len(), 3);
    assert_eq!(config.layers[0].rid, "low");
    assert_eq!(config.layers[2].rid, "high");
}

#[test]
fn test_quality_recommendation() {
    let rec = recommend_quality_preset(0.9, 5000.0, 2);
    assert_eq!(rec.preset, "hd");
    assert!(!rec.use_simulcast);

    let rec = recommend_quality_preset(0.2, 100.0, 2);
    assert_eq!(rec.preset, "low");

    let rec = recommend_quality_preset(0.7, 2000.0, 8);
    assert!(rec.use_simulcast);
}

#[test]
fn test_codec_preferences() {
    let prefs = get_codec_preferences();
    assert_eq!(prefs.audio_codecs[0], "opus");
    assert_eq!(prefs.video_codecs[0], "H264");
}
