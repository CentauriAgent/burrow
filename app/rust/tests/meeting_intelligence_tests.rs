use rust_lib_burrow_app::api::meeting_intelligence::*;
use rust_lib_burrow_app::api::transcription::TranscriptSegment;

fn make_segment(speaker: &str, text: &str, start_ms: i64) -> TranscriptSegment {
    TranscriptSegment {
        id: format!("seg_{}", start_ms),
        speaker_id: speaker.to_string(),
        speaker_name: speaker.to_string(),
        text: text.to_string(),
        start_ms,
        end_ms: start_ms + 3000,
        confidence: 0.9,
        language: "en".to_string(),
        is_final: true,
    }
}

#[test]
fn test_generate_notes_from_transcript() {
    let segments = vec![
        make_segment("Alice", "Let's discuss the Phase 4 plan", 0),
        make_segment("Bob", "I need to review the design doc by Friday", 3000),
        make_segment("Alice", "Agreed, let's go with the Rust approach", 6000),
        make_segment("Bob", "What about mobile testing?", 9000),
    ];

    let segments_json = serde_json::to_string(&segments).unwrap();
    let participants_json =
        serde_json::to_string(&vec!["alice_pub", "bob_pub"]).unwrap();

    let result = generate_meeting_notes(
        "test-meeting-001".to_string(),
        segments_json,
        participants_json,
        0,
        12_000,
    );

    assert!(result.is_ok());
    let notes_json = result.unwrap();
    let notes: MeetingNotes = serde_json::from_str(&notes_json).unwrap();

    assert_eq!(notes.meeting_id, "test-meeting-001");
    assert!(!notes.title.is_empty());
    assert!(!notes.summary.is_empty());
    assert!(!notes.action_items.is_empty()); // "need to" triggers
    assert!(!notes.decisions.is_empty()); // "let's go with" triggers
    assert!(!notes.open_questions.is_empty()); // "?" triggers
    assert_eq!(notes.participants.len(), 2);
}

#[test]
fn test_generate_notes_empty_transcript() {
    let result = generate_meeting_notes(
        "empty-meeting".to_string(),
        "[]".to_string(),
        "[\"alice\"]".to_string(),
        0,
        60_000,
    );

    assert!(result.is_ok());
    let notes: MeetingNotes = serde_json::from_str(&result.unwrap()).unwrap();
    assert!(notes.action_items.is_empty());
    assert!(notes.summary.contains("No transcript content"));
}

#[test]
fn test_action_item_priority() {
    let segments = vec![
        make_segment("Alice", "This is urgent, I need to fix this ASAP", 0),
        make_segment("Bob", "I should also look at the docs when I get a chance", 3000),
    ];

    let segments_json = serde_json::to_string(&segments).unwrap();
    let result = generate_meeting_notes(
        "priority-test".to_string(),
        segments_json,
        "[\"alice\", \"bob\"]".to_string(),
        0,
        6000,
    );

    let notes: MeetingNotes = serde_json::from_str(&result.unwrap()).unwrap();
    assert!(notes.action_items.len() >= 2);
    assert_eq!(notes.action_items[0].priority, "high");
}

#[test]
fn test_build_prompt() {
    let prompt = build_meeting_notes_prompt("Alice: Hello\nBob: Hi there".to_string()).unwrap();
    assert!(prompt.contains("Alice: Hello"));
    assert!(prompt.contains("action_items"));
    assert!(prompt.contains("key_points"));
}

#[test]
fn test_export_markdown() {
    // First generate notes to populate archive.
    let segments = vec![
        make_segment("Alice", "I need to write the tests", 0),
    ];
    let segments_json = serde_json::to_string(&segments).unwrap();
    let _ = generate_meeting_notes(
        "md-export-test".to_string(),
        segments_json,
        "[\"alice\"]".to_string(),
        0,
        30_000,
    );

    let md = export_meeting_markdown("md-export-test".to_string());
    assert!(md.is_ok());
    let content = md.unwrap();
    assert!(content.contains("# "));
    assert!(content.contains("Action Items"));
}

#[test]
fn test_search_meetings() {
    // Generate a meeting with known content.
    let segments = vec![
        make_segment("Alice", "We discussed the quantum computing roadmap", 0),
    ];
    let segments_json = serde_json::to_string(&segments).unwrap();
    let _ = generate_meeting_notes(
        "search-test".to_string(),
        segments_json,
        "[\"alice\"]".to_string(),
        0,
        10_000,
    );

    let result = search_meetings("quantum".to_string());
    assert!(result.is_ok());
    // Result should contain the meeting (may also contain others from shared state).
    let results_str = result.unwrap();
    assert!(results_str.contains("quantum") || results_str.contains("search-test"));
}

#[test]
fn test_configure_ai_backend() {
    let result = configure_ai_backend(r#""RuleBased""#.to_string());
    assert!(result.is_ok());

    let result = configure_ai_backend(
        r#"{"Ollama":{"model":"llama3","endpoint":"http://localhost:11434"}}"#.to_string(),
    );
    assert!(result.is_ok());
}

#[test]
fn test_configure_invalid_backend() {
    let result = configure_ai_backend("not valid json".to_string());
    assert!(result.is_err());
}

#[test]
fn test_get_meeting_archive() {
    let result = get_meeting_archive();
    assert!(result.is_ok());
}
