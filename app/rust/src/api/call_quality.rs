//! Audio/video codec configuration and adaptive quality optimization.
//!
//! Provides sensible defaults for mobile-first calling: battery-friendly codecs,
//! bandwidth-adaptive bitrate, and simulcast layers for SFU group calls.

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

// ── Audio Constraints ──────────────────────────────────────────────────────

/// Audio codec and processing configuration.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioConstraints {
    /// Sample rate in Hz (48000 for Opus).
    pub sample_rate: u32,
    /// Number of channels: 1 = mono (voice), 2 = stereo (music).
    pub channel_count: u32,
    /// Enable acoustic echo cancellation.
    pub echo_cancellation: bool,
    /// Enable noise suppression.
    pub noise_suppression: bool,
    /// Enable automatic gain control.
    pub auto_gain_control: bool,
    /// Target bitrate in bps. Opus voice: 24000-32000, music: 64000-128000.
    pub bitrate_bps: u32,
    /// Enable discontinuous transmission (saves bandwidth during silence).
    pub dtx_enabled: bool,
    /// Opus FEC for packet loss resilience.
    pub fec_enabled: bool,
    /// Packet time in ms (20 = default, 40/60 = lower overhead on constrained links).
    pub ptime_ms: u32,
}

/// Audio mode selection.
#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum AudioMode {
    /// Optimized for speech: mono, noise suppression, echo cancellation.
    Voice,
    /// Optimized for music sharing: stereo, no processing, higher bitrate.
    Music,
}

/// Get audio constraints for the given mode.
///
/// Voice mode: mono, 32kbps Opus, full processing pipeline, DTX + FEC.
/// Music mode: stereo, 96kbps Opus, no processing, no DTX.
#[frb]
pub fn get_audio_constraints(mode: AudioMode) -> AudioConstraints {
    match mode {
        AudioMode::Voice => AudioConstraints {
            sample_rate: 48000,
            channel_count: 1,
            echo_cancellation: true,
            noise_suppression: true,
            auto_gain_control: true,
            bitrate_bps: 32_000,
            dtx_enabled: true,
            fec_enabled: true,
            ptime_ms: 20,
        },
        AudioMode::Music => AudioConstraints {
            sample_rate: 48000,
            channel_count: 2,
            echo_cancellation: false,
            noise_suppression: false,
            auto_gain_control: false,
            bitrate_bps: 96_000,
            dtx_enabled: false,
            fec_enabled: false,
            ptime_ms: 20,
        },
    }
}

// ── Video Constraints ──────────────────────────────────────────────────────

/// Video quality preset.
#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum VideoQualityPreset {
    /// 320×240 @ 15fps, ~150kbps — minimal bandwidth / battery saver.
    Low,
    /// 640×480 @ 24fps, ~500kbps — good balance for mobile.
    Medium,
    /// 960×720 @ 30fps, ~1200kbps — high quality on Wi-Fi.
    High,
    /// 1280×720 @ 30fps, ~2500kbps — HD on strong connections.
    Hd,
}

/// Video resolution and bitrate constraints.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoConstraints {
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    /// Maximum send bitrate in bps.
    pub max_bitrate_bps: u32,
    /// Minimum send bitrate in bps.
    pub min_bitrate_bps: u32,
    /// Preferred codec name ("VP8", "H264", or "VP9").
    pub preferred_codec: String,
    /// Whether to request hardware acceleration.
    pub hardware_acceleration: bool,
}

/// Get video constraints for a given quality preset.
///
/// Presets are tuned for mobile: moderate resolutions, conservative bitrates,
/// hardware acceleration preferred for battery life.
#[frb]
pub fn get_video_constraints(preset: VideoQualityPreset) -> VideoConstraints {
    match preset {
        VideoQualityPreset::Low => VideoConstraints {
            width: 320,
            height: 240,
            frame_rate: 15,
            max_bitrate_bps: 150_000,
            min_bitrate_bps: 50_000,
            preferred_codec: "VP8".to_string(),
            hardware_acceleration: true,
        },
        VideoQualityPreset::Medium => VideoConstraints {
            width: 640,
            height: 480,
            frame_rate: 24,
            max_bitrate_bps: 500_000,
            min_bitrate_bps: 150_000,
            preferred_codec: "VP8".to_string(),
            hardware_acceleration: true,
        },
        VideoQualityPreset::High => VideoConstraints {
            width: 960,
            height: 720,
            frame_rate: 30,
            max_bitrate_bps: 1_200_000,
            min_bitrate_bps: 300_000,
            preferred_codec: "H264".to_string(),
            hardware_acceleration: true,
        },
        VideoQualityPreset::Hd => VideoConstraints {
            width: 1280,
            height: 720,
            frame_rate: 30,
            max_bitrate_bps: 2_500_000,
            min_bitrate_bps: 500_000,
            preferred_codec: "H264".to_string(),
            hardware_acceleration: true,
        },
    }
}

// ── Adaptive Bitrate ───────────────────────────────────────────────────────

/// Adaptive bitrate configuration for bandwidth estimation and quality stepping.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdaptiveBitrateConfig {
    /// If estimated bandwidth drops below this (bps), degrade quality.
    pub degradation_threshold_bps: u32,
    /// If estimated bandwidth rises above this (bps), try to recover quality.
    pub recovery_threshold_bps: u32,
    /// Minimum time (ms) between quality changes to avoid oscillation.
    pub hysteresis_ms: u32,
    /// Ordered list of video presets from worst to best for stepping.
    pub quality_steps: Vec<String>,
    /// Packet loss % above which we force degradation regardless of bandwidth.
    pub max_tolerable_loss_percent: f64,
    /// RTT (ms) above which we force degradation.
    pub max_tolerable_rtt_ms: f64,
}

/// Get default adaptive bitrate configuration.
///
/// Tuned for mobile: conservative thresholds, 3-second hysteresis to prevent
/// rapid quality oscillation on flaky cellular connections.
#[frb]
pub fn get_adaptive_bitrate_config() -> AdaptiveBitrateConfig {
    AdaptiveBitrateConfig {
        degradation_threshold_bps: 200_000,
        recovery_threshold_bps: 600_000,
        hysteresis_ms: 3_000,
        quality_steps: vec![
            "low".to_string(),
            "medium".to_string(),
            "high".to_string(),
            "hd".to_string(),
        ],
        max_tolerable_loss_percent: 5.0,
        max_tolerable_rtt_ms: 400.0,
    }
}

// ── Quality Score ──────────────────────────────────────────────────────────

/// Composite quality score result.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityScore {
    /// Overall score 0.0 (unusable) to 1.0 (excellent).
    pub score: f64,
    /// Human-readable label: "excellent", "good", "fair", "poor", "unusable".
    pub label: String,
    /// Per-metric breakdown.
    pub rtt_score: f64,
    pub jitter_score: f64,
    pub loss_score: f64,
    pub bitrate_score: f64,
}

/// Calculate a composite quality score from network metrics.
///
/// Weights: RTT 25%, jitter 20%, packet loss 35%, bitrate adequacy 20%.
/// Packet loss is weighted highest because it has the most audible impact.
#[frb]
pub fn calculate_quality_score(
    rtt_ms: f64,
    jitter_ms: f64,
    packet_loss_percent: f64,
    bitrate_kbps: f64,
    is_video: bool,
) -> QualityScore {
    let rtt_score = score_rtt(rtt_ms);
    let jitter_score = score_jitter(jitter_ms);
    let loss_score = score_loss(packet_loss_percent);
    let bitrate_score = score_bitrate(bitrate_kbps, is_video);

    let score = rtt_score * 0.25 + jitter_score * 0.20 + loss_score * 0.35 + bitrate_score * 0.20;
    let score = score.clamp(0.0, 1.0);

    let label = if score >= 0.85 {
        "excellent"
    } else if score >= 0.65 {
        "good"
    } else if score >= 0.45 {
        "fair"
    } else if score >= 0.25 {
        "poor"
    } else {
        "unusable"
    }
    .to_string();

    QualityScore {
        score,
        label,
        rtt_score,
        jitter_score,
        loss_score,
        bitrate_score,
    }
}

fn score_rtt(rtt: f64) -> f64 {
    if rtt <= 50.0 { 1.0 }
    else if rtt <= 100.0 { 0.9 }
    else if rtt <= 200.0 { 0.7 }
    else if rtt <= 350.0 { 0.4 }
    else if rtt <= 500.0 { 0.2 }
    else { 0.05 }
}

fn score_jitter(jitter: f64) -> f64 {
    if jitter <= 10.0 { 1.0 }
    else if jitter <= 30.0 { 0.8 }
    else if jitter <= 50.0 { 0.6 }
    else if jitter <= 100.0 { 0.3 }
    else { 0.1 }
}

fn score_loss(loss: f64) -> f64 {
    if loss <= 0.5 { 1.0 }
    else if loss <= 2.0 { 0.8 }
    else if loss <= 5.0 { 0.5 }
    else if loss <= 10.0 { 0.25 }
    else { 0.05 }
}

fn score_bitrate(kbps: f64, is_video: bool) -> f64 {
    if is_video {
        // Video: need at least ~150kbps for usable quality
        if kbps >= 1200.0 { 1.0 }
        else if kbps >= 500.0 { 0.8 }
        else if kbps >= 250.0 { 0.6 }
        else if kbps >= 100.0 { 0.3 }
        else { 0.1 }
    } else {
        // Audio: need at least ~16kbps for usable Opus
        if kbps >= 48.0 { 1.0 }
        else if kbps >= 32.0 { 0.9 }
        else if kbps >= 20.0 { 0.6 }
        else if kbps >= 12.0 { 0.3 }
        else { 0.1 }
    }
}

// ── Simulcast Configuration ────────────────────────────────────────────────

/// A single simulcast layer.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulcastLayer {
    /// Layer identifier: "low", "medium", "high".
    pub rid: String,
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub max_bitrate_bps: u32,
    /// Scale-down factor relative to capture resolution (e.g. 4.0 = 1/4 res).
    pub scale_resolution_down_by: f64,
}

/// Full simulcast configuration for SFU group calls.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulcastConfig {
    /// Whether simulcast is enabled.
    pub enabled: bool,
    /// Ordered layers from lowest to highest quality.
    pub layers: Vec<SimulcastLayer>,
}

/// Get simulcast configuration for SFU group calls.
///
/// Three layers: low (180p), medium (360p), high (720p).
/// The SFU selects which layer to forward based on each receiver's bandwidth.
#[frb]
pub fn get_simulcast_config() -> SimulcastConfig {
    SimulcastConfig {
        enabled: true,
        layers: vec![
            SimulcastLayer {
                rid: "low".to_string(),
                width: 320,
                height: 180,
                frame_rate: 15,
                max_bitrate_bps: 125_000,
                scale_resolution_down_by: 4.0,
            },
            SimulcastLayer {
                rid: "medium".to_string(),
                width: 640,
                height: 360,
                frame_rate: 24,
                max_bitrate_bps: 500_000,
                scale_resolution_down_by: 2.0,
            },
            SimulcastLayer {
                rid: "high".to_string(),
                width: 1280,
                height: 720,
                frame_rate: 30,
                max_bitrate_bps: 1_500_000,
                scale_resolution_down_by: 1.0,
            },
        ],
    }
}

// ── Quality Preset Recommendation ──────────────────────────────────────────

/// Recommended quality preset with reasoning.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityRecommendation {
    /// Recommended video preset name: "low", "medium", "high", "hd".
    pub preset: String,
    /// Recommended audio mode: "voice" or "music".
    pub audio_mode: String,
    /// Whether simulcast should be enabled.
    pub use_simulcast: bool,
    /// Human-readable reason for the recommendation.
    pub reason: String,
}

/// Recommend a quality preset based on network conditions and call context.
///
/// Takes into account estimated bandwidth, current quality score, and
/// participant count (more participants = lower per-user bandwidth).
#[frb]
pub fn recommend_quality_preset(
    quality_score: f64,
    estimated_bandwidth_kbps: f64,
    participant_count: u32,
) -> QualityRecommendation {
    let use_simulcast = participant_count > 2;

    // Per-user available bandwidth (rough estimate for mesh/SFU)
    let per_user_bw = if participant_count > 1 {
        estimated_bandwidth_kbps / (participant_count as f64 - 1.0).max(1.0)
    } else {
        estimated_bandwidth_kbps
    };

    let (preset, reason) = if quality_score < 0.3 || per_user_bw < 150.0 {
        ("low", "Poor network conditions or very limited bandwidth")
    } else if quality_score < 0.5 || per_user_bw < 500.0 || participant_count > 6 {
        ("medium", "Moderate conditions or many participants")
    } else if quality_score < 0.75 || per_user_bw < 1500.0 || participant_count > 3 {
        ("high", "Good conditions, balanced quality")
    } else {
        ("hd", "Excellent conditions, low participant count")
    };

    QualityRecommendation {
        preset: preset.to_string(),
        audio_mode: "voice".to_string(),
        use_simulcast,
        reason: reason.to_string(),
    }
}

// ── Codec Preference for SDP Munging ───────────────────────────────────────

/// Preferred codec ordering for SDP manipulation.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodecPreferences {
    /// Ordered audio codec preferences (first = most preferred).
    pub audio_codecs: Vec<String>,
    /// Ordered video codec preferences.
    pub video_codecs: Vec<String>,
}

/// Get codec preferences for SDP munging.
///
/// Audio: Opus is the only real choice for WebRTC (mandatory-to-implement).
/// Video: Prefer H264 (hardware acceleration on most mobile) > VP8 (universal fallback) > VP9.
#[frb]
pub fn get_codec_preferences() -> CodecPreferences {
    CodecPreferences {
        audio_codecs: vec!["opus".to_string()],
        video_codecs: vec![
            "H264".to_string(),
            "VP8".to_string(),
            "VP9".to_string(),
        ],
    }
}
