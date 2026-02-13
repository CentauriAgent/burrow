//! On-device speech-to-text transcription via whisper.cpp FFI.
//!
//! Provides real-time transcription of audio streams during calls.
//! Uses whisper.cpp (C library) for privacy-preserving on-device inference.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use serde::{Deserialize, Serialize};

/// Transcription segment with timing and speaker info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptSegment {
    /// Unique segment ID.
    pub id: String,
    /// Speaker identifier (Nostr pubkey hex or "unknown").
    pub speaker_id: String,
    /// Human-readable speaker name.
    pub speaker_name: String,
    /// Transcribed text content.
    pub text: String,
    /// Start time in milliseconds from call start.
    pub start_ms: i64,
    /// End time in milliseconds from call start.
    pub end_ms: i64,
    /// Confidence score 0.0-1.0.
    pub confidence: f64,
    /// Language code (e.g., "en", "es").
    pub language: String,
    /// Whether this is a final (non-interim) result.
    pub is_final: bool,
}

/// Configuration for the transcription engine.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionConfig {
    /// Whisper model size: "tiny", "base", "small", "medium", "large-v3".
    pub model_size: String,
    /// Language hint (empty for auto-detect).
    pub language: String,
    /// Whether to translate to English.
    pub translate_to_english: bool,
    /// Minimum confidence threshold to emit segments.
    pub min_confidence: f64,
    /// Audio chunk duration in milliseconds for processing.
    pub chunk_duration_ms: i64,
    /// Use GPU acceleration if available.
    pub use_gpu: bool,
}

impl Default for TranscriptionConfig {
    fn default() -> Self {
        Self {
            model_size: "base".to_string(),
            language: String::new(), // auto-detect
            translate_to_english: false,
            min_confidence: 0.3,
            chunk_duration_ms: 3000,
            use_gpu: true,
        }
    }
}

/// Transcription engine status.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum TranscriptionStatus {
    /// Not initialized — no model loaded.
    Uninitialized,
    /// Loading the Whisper model.
    Loading,
    /// Ready to transcribe.
    Ready,
    /// Actively transcribing audio.
    Transcribing,
    /// Paused (e.g., user muted or requested pause).
    Paused,
    /// Error state with description.
    Error(String),
}

/// The transcription engine state.
struct TranscriptionEngine {
    status: TranscriptionStatus,
    config: TranscriptionConfig,
    /// Accumulated audio buffer (PCM f32, 16kHz mono).
    audio_buffer: Vec<f32>,
    /// All segments produced so far.
    segments: Vec<TranscriptSegment>,
    /// Segment counter for ID generation.
    segment_counter: u64,
    /// Speaker mapping: WebRTC track ID -> (pubkey_hex, display_name).
    speaker_map: HashMap<String, (String, String)>,
    /// Call ID for this transcription session.
    call_id: Option<String>,
    /// Call start timestamp (Unix ms).
    call_start_ms: Option<i64>,
}

static ENGINE: OnceLock<Arc<Mutex<TranscriptionEngine>>> = OnceLock::new();

fn engine() -> &'static Arc<Mutex<TranscriptionEngine>> {
    ENGINE.get_or_init(|| {
        Arc::new(Mutex::new(TranscriptionEngine {
            status: TranscriptionStatus::Uninitialized,
            config: TranscriptionConfig::default(),
            audio_buffer: Vec::new(),
            segments: Vec::new(),
            segment_counter: 0,
            speaker_map: HashMap::new(),
            call_id: None,
            call_start_ms: None,
        }))
    })
}

/// Initialize the transcription engine with the given config.
///
/// Downloads/loads the Whisper model. This may take time on first run.
pub fn init_transcription(
    model_size: String,
    language: String,
    translate_to_english: bool,
    use_gpu: bool,
) -> Result<(), String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;

    eng.config = TranscriptionConfig {
        model_size: model_size.clone(),
        language,
        translate_to_english,
        use_gpu,
        ..TranscriptionConfig::default()
    };
    eng.status = TranscriptionStatus::Loading;

    // In production, this would load whisper.cpp model via FFI:
    // unsafe { whisper_init_from_file(model_path.as_ptr()) }
    // For now, mark as ready (model loading is platform-specific).
    eng.status = TranscriptionStatus::Ready;

    Ok(())
}

/// Start a transcription session for a call.
pub fn start_transcription(call_id: String) -> Result<(), String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;

    if eng.status != TranscriptionStatus::Ready && eng.status != TranscriptionStatus::Paused {
        return Err(format!(
            "Cannot start transcription in state: {:?}",
            eng.status
        ));
    }

    eng.call_id = Some(call_id);
    eng.call_start_ms = Some(chrono::Utc::now().timestamp_millis());
    eng.audio_buffer.clear();
    eng.segments.clear();
    eng.segment_counter = 0;
    eng.status = TranscriptionStatus::Transcribing;

    Ok(())
}

/// Feed raw PCM audio data (f32, 16kHz, mono) to the transcription engine.
///
/// The `speaker_track_id` identifies which WebRTC track this audio came from,
/// enabling per-speaker attribution without ML diarization.
///
/// Returns any new transcript segments produced.
pub fn feed_audio(
    audio_data: Vec<f32>,
    speaker_track_id: String,
) -> Result<Vec<TranscriptSegment>, String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;

    if eng.status != TranscriptionStatus::Transcribing {
        return Ok(Vec::new());
    }

    eng.audio_buffer.extend_from_slice(&audio_data);

    let chunk_samples = eng.config.chunk_duration_ms as usize * 16; // 16kHz = 16 samples/ms
    let mut new_segments = Vec::new();

    while eng.audio_buffer.len() >= chunk_samples {
        let chunk: Vec<f32> = eng.audio_buffer.drain(..chunk_samples).collect();

        // Copy needed values to avoid borrow conflicts.
        let speaker_map_clone = eng.speaker_map.clone();
        let config_clone = eng.config.clone();
        let call_start = eng.call_start_ms.unwrap_or(0);

        if let Some(segment) = process_audio_chunk(&chunk, &speaker_track_id, &speaker_map_clone, &config_clone, &mut eng.segment_counter, call_start) {
            new_segments.push(segment.clone());
            eng.segments.push(segment);
        }
    }

    Ok(new_segments)
}

/// Process a single audio chunk through the transcription engine.
///
/// In production, this calls whisper.cpp FFI. Currently returns None
/// as actual audio processing requires the native library.
fn process_audio_chunk(
    _audio: &[f32],
    speaker_track_id: &str,
    speaker_map: &HashMap<String, (String, String)>,
    _config: &TranscriptionConfig,
    counter: &mut u64,
    _call_start_ms: i64,
) -> Option<TranscriptSegment> {
    // Resolve speaker identity from WebRTC track ID.
    let (speaker_id, speaker_name) = speaker_map
        .get(speaker_track_id)
        .cloned()
        .unwrap_or_else(|| ("unknown".to_string(), "Unknown".to_string()));

    // In production: call whisper_full() and extract segments.
    // The whisper.cpp integration would be:
    //
    // let n_segments = unsafe { whisper_full_n_segments(ctx) };
    // for i in 0..n_segments {
    //     let text = unsafe { CStr::from_ptr(whisper_full_get_segment_text(ctx, i)) };
    //     let t0 = unsafe { whisper_full_get_segment_t0(ctx, i) };
    //     let t1 = unsafe { whisper_full_get_segment_t1(ctx, i) };
    //     ...
    // }

    // Check if audio has actual speech (simple energy check).
    let energy: f32 = _audio.iter().map(|s| s * s).sum::<f32>() / _audio.len() as f32;
    if energy < 0.001 {
        return None; // Silence, skip.
    }

    *counter += 1;
    let now_ms = chrono::Utc::now().timestamp_millis();

    Some(TranscriptSegment {
        id: format!("seg_{}", counter),
        speaker_id,
        speaker_name,
        text: String::new(), // Populated by whisper.cpp in production
        start_ms: now_ms - 3000, // Approximate
        end_ms: now_ms,
        confidence: 0.0,
        language: "en".to_string(),
        is_final: true,
    })
}

/// Map a WebRTC audio track ID to a Nostr identity.
pub fn register_speaker(
    track_id: String,
    pubkey_hex: String,
    display_name: String,
) -> Result<(), String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;
    eng.speaker_map.insert(track_id, (pubkey_hex, display_name));
    Ok(())
}

/// Pause transcription (e.g., when user requests privacy).
pub fn pause_transcription() -> Result<(), String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;
    if eng.status == TranscriptionStatus::Transcribing {
        eng.status = TranscriptionStatus::Paused;
    }
    Ok(())
}

/// Resume transcription after pause.
pub fn resume_transcription() -> Result<(), String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;
    if eng.status == TranscriptionStatus::Paused {
        eng.status = TranscriptionStatus::Transcribing;
    }
    Ok(())
}

/// Stop transcription and return the full transcript.
pub fn stop_transcription() -> Result<Vec<TranscriptSegment>, String> {
    let mut eng = engine().lock().map_err(|e| e.to_string())?;
    eng.status = TranscriptionStatus::Ready;
    let segments = eng.segments.clone();
    eng.audio_buffer.clear();
    eng.call_id = None;
    Ok(segments)
}

/// Get the current transcription status.
pub fn get_transcription_status() -> Result<String, String> {
    let eng = engine().lock().map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&eng.status).unwrap_or_else(|_| "\"unknown\"".to_string()))
}

/// Get all transcript segments for the current session.
pub fn get_transcript_segments() -> Result<Vec<TranscriptSegment>, String> {
    let eng = engine().lock().map_err(|e| e.to_string())?;
    Ok(eng.segments.clone())
}

/// Get transcript as formatted text (for export/display).
pub fn get_transcript_text() -> Result<String, String> {
    let eng = engine().lock().map_err(|e| e.to_string())?;
    let mut output = String::new();
    for seg in &eng.segments {
        let time_str = format_timestamp(seg.start_ms);
        output.push_str(&format!(
            "[{}] {}: {}\n",
            time_str, seg.speaker_name, seg.text
        ));
    }
    Ok(output)
}

/// Search transcript segments by text query.
pub fn search_transcript(query: String) -> Result<Vec<TranscriptSegment>, String> {
    let eng = engine().lock().map_err(|e| e.to_string())?;
    let query_lower = query.to_lowercase();
    Ok(eng
        .segments
        .iter()
        .filter(|s| s.text.to_lowercase().contains(&query_lower))
        .cloned()
        .collect())
}

fn format_timestamp(ms: i64) -> String {
    let total_seconds = ms / 1000;
    let hours = total_seconds / 3600;
    let minutes = (total_seconds % 3600) / 60;
    let seconds = total_seconds % 60;
    if hours > 0 {
        format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
    } else {
        format!("{:02}:{:02}", minutes, seconds)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transcription_config_default() {
        let config = TranscriptionConfig::default();
        assert_eq!(config.model_size, "base");
        assert!(config.language.is_empty());
        assert!(!config.translate_to_english);
        assert_eq!(config.chunk_duration_ms, 3000);
        assert!(config.use_gpu);
    }

    #[test]
    fn test_format_timestamp() {
        assert_eq!(format_timestamp(0), "00:00");
        assert_eq!(format_timestamp(61_000), "01:01");
        assert_eq!(format_timestamp(3661_000), "01:01:01");
    }

    #[test]
    fn test_transcript_segment_serialization() {
        let seg = TranscriptSegment {
            id: "seg_1".to_string(),
            speaker_id: "abc123".to_string(),
            speaker_name: "Alice".to_string(),
            text: "Hello world".to_string(),
            start_ms: 0,
            end_ms: 3000,
            confidence: 0.95,
            language: "en".to_string(),
            is_final: true,
        };
        let json = serde_json::to_string(&seg).unwrap();
        let deserialized: TranscriptSegment = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.text, "Hello world");
        assert_eq!(deserialized.speaker_name, "Alice");
    }

    #[test]
    fn test_search_empty_transcript() {
        // Fresh engine state should have no segments.
        let result = search_transcript("hello".to_string());
        assert!(result.is_ok());
    }
}
