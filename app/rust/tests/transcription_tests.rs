use rust_lib_burrow_app::api::transcription::*;

#[test]
fn test_config_defaults() {
    let config = TranscriptionConfig::default();
    assert_eq!(config.model_size, "base");
    assert!(config.language.is_empty());
    assert!(!config.translate_to_english);
    assert!(config.use_gpu);
    assert_eq!(config.chunk_duration_ms, 3000);
    assert_eq!(config.min_confidence, 0.3);
}

#[test]
fn test_transcript_segment_roundtrip() {
    let seg = TranscriptSegment {
        id: "seg_42".to_string(),
        speaker_id: "abc123def456".to_string(),
        speaker_name: "Alice".to_string(),
        text: "Let's discuss the roadmap".to_string(),
        start_ms: 5000,
        end_ms: 8000,
        confidence: 0.92,
        language: "en".to_string(),
        is_final: true,
    };

    let json = serde_json::to_string(&seg).unwrap();
    let decoded: TranscriptSegment = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded.id, "seg_42");
    assert_eq!(decoded.speaker_name, "Alice");
    assert_eq!(decoded.text, "Let's discuss the roadmap");
    assert_eq!(decoded.start_ms, 5000);
    assert!((decoded.confidence - 0.92).abs() < f64::EPSILON);
}

#[test]
fn test_get_transcription_status_default() {
    let status = get_transcription_status();
    assert!(status.is_ok());
}

#[test]
fn test_register_speaker() {
    let result = register_speaker(
        "track_001".to_string(),
        "abcdef1234".to_string(),
        "Bob".to_string(),
    );
    assert!(result.is_ok());
}

#[test]
fn test_search_transcript_empty() {
    let result = search_transcript("nonexistent".to_string());
    assert!(result.is_ok());
    assert!(result.unwrap().is_empty());
}

#[test]
fn test_get_transcript_text_empty() {
    let result = get_transcript_text();
    assert!(result.is_ok());
}
