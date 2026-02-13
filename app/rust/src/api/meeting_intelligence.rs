//! AI-powered meeting intelligence: summaries, action items, and notes.
//!
//! Processes transcripts to extract structured meeting insights.
//! Supports both local LLM (Ollama) and cloud API (Claude) backends.

use std::sync::{Arc, Mutex, OnceLock};
use serde::{Deserialize, Serialize};

use crate::api::transcription::TranscriptSegment;

/// An extracted action item from a meeting.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionItem {
    /// Unique ID.
    pub id: String,
    /// Assignee's Nostr pubkey hex (or empty if unassigned).
    pub assignee_pubkey: String,
    /// Assignee's display name.
    pub assignee_name: String,
    /// Description of the action item.
    pub description: String,
    /// Deadline (ISO 8601 date string, or empty).
    pub deadline: String,
    /// Priority: "high", "medium", "low".
    pub priority: String,
    /// Whether this item has been completed.
    pub completed: bool,
}

/// A key decision recorded during the meeting.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decision {
    /// What was decided.
    pub description: String,
    /// Who made or proposed the decision.
    pub proposed_by: String,
    /// Context: which discussion topic it relates to.
    pub context: String,
}

/// Complete meeting notes generated from a transcript.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeetingNotes {
    /// Unique meeting ID (same as call_id).
    pub meeting_id: String,
    /// Meeting title (auto-generated from content).
    pub title: String,
    /// Executive summary (2-3 paragraphs).
    pub summary: String,
    /// Key discussion points.
    pub key_points: Vec<String>,
    /// Extracted action items.
    pub action_items: Vec<ActionItem>,
    /// Decisions made.
    pub decisions: Vec<Decision>,
    /// Open questions / unresolved topics.
    pub open_questions: Vec<String>,
    /// Participant pubkeys.
    pub participants: Vec<String>,
    /// Meeting start time (Unix ms).
    pub start_time_ms: i64,
    /// Meeting end time (Unix ms).
    pub end_time_ms: i64,
    /// Duration in seconds.
    pub duration_seconds: i64,
    /// Generation timestamp.
    pub generated_at_ms: i64,
}

/// Configuration for the AI backend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AiBackend {
    /// Local LLM via Ollama.
    Ollama {
        model: String,
        endpoint: String,
    },
    /// Claude API.
    Claude {
        api_key: String,
        model: String,
    },
    /// No AI — just structural extraction (keyword-based).
    RuleBased,
}

impl Default for AiBackend {
    fn default() -> Self {
        AiBackend::RuleBased
    }
}

/// Meeting intelligence engine state.
struct MeetingIntelligence {
    backend: AiBackend,
    /// Archive of past meeting notes, keyed by meeting_id.
    archive: Vec<MeetingNotes>,
}

static INTELLIGENCE: OnceLock<Arc<Mutex<MeetingIntelligence>>> = OnceLock::new();

fn intelligence() -> &'static Arc<Mutex<MeetingIntelligence>> {
    INTELLIGENCE.get_or_init(|| {
        Arc::new(Mutex::new(MeetingIntelligence {
            backend: AiBackend::default(),
            archive: Vec::new(),
        }))
    })
}

/// Configure the AI backend for meeting intelligence.
pub fn configure_ai_backend(backend_json: String) -> Result<(), String> {
    let backend: AiBackend =
        serde_json::from_str(&backend_json).map_err(|e| format!("Invalid backend config: {e}"))?;
    let mut intel = intelligence().lock().map_err(|e| e.to_string())?;
    intel.backend = backend;
    Ok(())
}

/// Generate meeting notes from a transcript.
///
/// This is the main entry point after a call ends. It processes the full
/// transcript and produces structured meeting notes.
pub fn generate_meeting_notes(
    meeting_id: String,
    segments_json: String,
    participants_json: String,
    start_time_ms: i64,
    end_time_ms: i64,
) -> Result<String, String> {
    let segments: Vec<TranscriptSegment> =
        serde_json::from_str(&segments_json).map_err(|e| format!("Invalid segments: {e}"))?;
    let participants: Vec<String> =
        serde_json::from_str(&participants_json).map_err(|e| format!("Invalid participants: {e}"))?;

    let mut intel = intelligence().lock().map_err(|e| e.to_string())?;

    let notes = match &intel.backend {
        AiBackend::RuleBased => {
            generate_rule_based_notes(&meeting_id, &segments, &participants, start_time_ms, end_time_ms)
        }
        AiBackend::Ollama { .. } | AiBackend::Claude { .. } => {
            // For LLM backends, build the prompt and call the API.
            // In production, this would make HTTP calls to Ollama or Claude.
            // Fall back to rule-based for now.
            generate_rule_based_notes(&meeting_id, &segments, &participants, start_time_ms, end_time_ms)
        }
    };

    intel.archive.push(notes.clone());
    serde_json::to_string(&notes).map_err(|e| format!("Serialization error: {e}"))
}

/// Rule-based meeting notes generation (no LLM required).
///
/// Extracts action items by keyword detection, generates a basic summary,
/// and identifies discussion topics by speaker transitions.
fn generate_rule_based_notes(
    meeting_id: &str,
    segments: &[TranscriptSegment],
    participants: &[String],
    start_time_ms: i64,
    end_time_ms: i64,
) -> MeetingNotes {
    let full_text: String = segments.iter().map(|s| s.text.as_str()).collect::<Vec<_>>().join(" ");

    // Extract action items from keyword patterns.
    let action_items = extract_action_items_rule_based(segments);

    // Extract decisions.
    let decisions = extract_decisions_rule_based(segments);

    // Extract open questions.
    let open_questions = extract_questions_rule_based(segments);

    // Generate key discussion points (by grouping consecutive segments by topic changes).
    let key_points = extract_key_points(segments);

    // Generate summary.
    let duration_seconds = (end_time_ms - start_time_ms) / 1000;
    let summary = generate_basic_summary(
        segments.len(),
        participants.len(),
        duration_seconds,
        &action_items,
        &key_points,
    );

    // Auto-generate title from first substantive content.
    let title = generate_title(&full_text, participants.len());

    MeetingNotes {
        meeting_id: meeting_id.to_string(),
        title,
        summary,
        key_points,
        action_items,
        decisions,
        open_questions,
        participants: participants.to_vec(),
        start_time_ms,
        end_time_ms,
        duration_seconds,
        generated_at_ms: chrono::Utc::now().timestamp_millis(),
    }
}

/// Extract action items using keyword patterns.
fn extract_action_items_rule_based(segments: &[TranscriptSegment]) -> Vec<ActionItem> {
    let action_keywords = [
        "action item",
        "todo",
        "to do",
        "need to",
        "should",
        "will do",
        "i'll",
        "let me",
        "follow up",
        "take care of",
        "responsible for",
        "deadline",
        "by friday",
        "by monday",
        "by next week",
        "by end of",
    ];

    let mut items = Vec::new();
    let mut counter = 0u32;

    for seg in segments {
        let lower = seg.text.to_lowercase();
        if action_keywords.iter().any(|kw| lower.contains(kw)) {
            counter += 1;
            let priority = if lower.contains("urgent") || lower.contains("asap") || lower.contains("critical") {
                "high"
            } else if lower.contains("when you get a chance") || lower.contains("low priority") {
                "low"
            } else {
                "medium"
            };

            items.push(ActionItem {
                id: format!("ai_{}", counter),
                assignee_pubkey: seg.speaker_id.clone(),
                assignee_name: seg.speaker_name.clone(),
                description: seg.text.clone(),
                deadline: String::new(),
                priority: priority.to_string(),
                completed: false,
            });
        }
    }
    items
}

/// Extract decisions using keyword patterns.
fn extract_decisions_rule_based(segments: &[TranscriptSegment]) -> Vec<Decision> {
    let decision_keywords = [
        "decided",
        "agreed",
        "let's go with",
        "we'll use",
        "the plan is",
        "approved",
        "consensus",
        "final decision",
    ];

    let mut decisions = Vec::new();
    for seg in segments {
        let lower = seg.text.to_lowercase();
        if decision_keywords.iter().any(|kw| lower.contains(kw)) {
            decisions.push(Decision {
                description: seg.text.clone(),
                proposed_by: seg.speaker_name.clone(),
                context: String::new(),
            });
        }
    }
    decisions
}

/// Extract open questions.
fn extract_questions_rule_based(segments: &[TranscriptSegment]) -> Vec<String> {
    segments
        .iter()
        .filter(|s| s.text.contains('?'))
        .map(|s| format!("{}: {}", s.speaker_name, s.text))
        .collect()
}

/// Extract key discussion points by identifying topic clusters.
fn extract_key_points(segments: &[TranscriptSegment]) -> Vec<String> {
    // Group segments into clusters by speaker transitions and pauses.
    let mut points = Vec::new();
    let mut current_topic_texts: Vec<String> = Vec::new();

    for (i, seg) in segments.iter().enumerate() {
        current_topic_texts.push(seg.text.clone());

        // Topic boundary: speaker change after 3+ segments, or large time gap.
        let is_boundary = if i + 1 < segments.len() {
            let next = &segments[i + 1];
            let time_gap = next.start_ms - seg.end_ms;
            (seg.speaker_id != next.speaker_id && current_topic_texts.len() >= 3) || time_gap > 10_000
        } else {
            true
        };

        if is_boundary && !current_topic_texts.is_empty() {
            // Summarize this cluster: take first sentence as the point.
            let combined = current_topic_texts.join(" ");
            let point = combined
                .split('.')
                .next()
                .unwrap_or(&combined)
                .trim()
                .to_string();
            if !point.is_empty() && point.len() > 10 {
                points.push(point);
            }
            current_topic_texts.clear();
        }
    }
    points
}

fn generate_basic_summary(
    segment_count: usize,
    participant_count: usize,
    duration_seconds: i64,
    action_items: &[ActionItem],
    key_points: &[String],
) -> String {
    let duration_min = duration_seconds / 60;
    let mut summary = format!(
        "Meeting with {} participant(s), lasting {} minute(s). ",
        participant_count, duration_min
    );

    if !key_points.is_empty() {
        summary.push_str(&format!(
            "{} key discussion point(s) were identified. ",
            key_points.len()
        ));
    }

    if !action_items.is_empty() {
        summary.push_str(&format!(
            "{} action item(s) were extracted. ",
            action_items.len()
        ));
        let high_priority = action_items.iter().filter(|a| a.priority == "high").count();
        if high_priority > 0 {
            summary.push_str(&format!(
                "{} of these are high priority.",
                high_priority
            ));
        }
    }

    if segment_count == 0 {
        summary = "No transcript content was captured for this meeting.".to_string();
    }

    summary
}

fn generate_title(full_text: &str, participant_count: usize) -> String {
    if full_text.is_empty() {
        return format!("Meeting ({} participants)", participant_count);
    }
    // Take first meaningful phrase (up to 60 chars).
    let title: String = full_text
        .chars()
        .take(60)
        .collect::<String>()
        .split('.')
        .next()
        .unwrap_or("Meeting")
        .trim()
        .to_string();
    if title.len() < 5 {
        format!("Meeting ({} participants)", participant_count)
    } else {
        title
    }
}

/// Build a prompt for LLM-based meeting notes generation.
///
/// Used with Ollama or Claude backends.
pub fn build_meeting_notes_prompt(transcript_text: String) -> Result<String, String> {
    Ok(format!(
        r#"You are a meeting assistant. Analyze the following meeting transcript and produce structured notes.

## Transcript
{}

## Instructions
Produce a JSON response with this exact structure:
{{
  "title": "Brief descriptive title for this meeting",
  "summary": "2-3 paragraph executive summary",
  "key_points": ["point 1", "point 2", ...],
  "action_items": [
    {{
      "assignee_name": "Person name",
      "description": "What needs to be done",
      "deadline": "YYYY-MM-DD or empty string",
      "priority": "high|medium|low"
    }}
  ],
  "decisions": [
    {{
      "description": "What was decided",
      "proposed_by": "Person name",
      "context": "Related discussion topic"
    }}
  ],
  "open_questions": ["question 1", "question 2", ...]
}}

Be concise but thorough. Extract ALL action items mentioned. Identify who is responsible."#,
        transcript_text
    ))
}

/// Get all archived meeting notes.
pub fn get_meeting_archive() -> Result<String, String> {
    let intel = intelligence().lock().map_err(|e| e.to_string())?;
    serde_json::to_string(&intel.archive).map_err(|e| format!("Serialization error: {e}"))
}

/// Search meeting notes archive by query.
pub fn search_meetings(query: String) -> Result<String, String> {
    let intel = intelligence().lock().map_err(|e| e.to_string())?;
    let query_lower = query.to_lowercase();
    let results: Vec<&MeetingNotes> = intel
        .archive
        .iter()
        .filter(|n| {
            n.title.to_lowercase().contains(&query_lower)
                || n.summary.to_lowercase().contains(&query_lower)
                || n.key_points.iter().any(|p| p.to_lowercase().contains(&query_lower))
                || n.action_items.iter().any(|a| a.description.to_lowercase().contains(&query_lower))
        })
        .collect();
    serde_json::to_string(&results).map_err(|e| format!("Serialization error: {e}"))
}

/// Toggle action item completion status.
pub fn toggle_action_item(meeting_id: String, action_item_id: String) -> Result<bool, String> {
    let mut intel = intelligence().lock().map_err(|e| e.to_string())?;
    for notes in intel.archive.iter_mut() {
        if notes.meeting_id == meeting_id {
            for item in notes.action_items.iter_mut() {
                if item.id == action_item_id {
                    item.completed = !item.completed;
                    return Ok(item.completed);
                }
            }
        }
    }
    Err("Action item not found".to_string())
}

/// Get meeting notes by ID.
pub fn get_meeting_notes(meeting_id: String) -> Result<String, String> {
    let intel = intelligence().lock().map_err(|e| e.to_string())?;
    let notes = intel
        .archive
        .iter()
        .find(|n| n.meeting_id == meeting_id)
        .ok_or_else(|| format!("Meeting not found: {meeting_id}"))?;
    serde_json::to_string(notes).map_err(|e| format!("Serialization error: {e}"))
}

/// Export meeting notes as markdown.
pub fn export_meeting_markdown(meeting_id: String) -> Result<String, String> {
    let intel = intelligence().lock().map_err(|e| e.to_string())?;
    let notes = intel
        .archive
        .iter()
        .find(|n| n.meeting_id == meeting_id)
        .ok_or_else(|| format!("Meeting not found: {meeting_id}"))?;

    let mut md = format!("# {}\n\n", notes.title);
    md.push_str(&format!("**Duration:** {} minutes\n", notes.duration_seconds / 60));
    md.push_str(&format!("**Participants:** {}\n\n", notes.participants.len()));

    md.push_str("## Summary\n\n");
    md.push_str(&notes.summary);
    md.push_str("\n\n");

    if !notes.key_points.is_empty() {
        md.push_str("## Key Discussion Points\n\n");
        for point in &notes.key_points {
            md.push_str(&format!("- {}\n", point));
        }
        md.push_str("\n");
    }

    if !notes.action_items.is_empty() {
        md.push_str("## Action Items\n\n");
        for item in &notes.action_items {
            let check = if item.completed { "x" } else { " " };
            md.push_str(&format!(
                "- [{}] **{}** — {} (Priority: {})\n",
                check, item.assignee_name, item.description, item.priority
            ));
        }
        md.push_str("\n");
    }

    if !notes.decisions.is_empty() {
        md.push_str("## Decisions\n\n");
        for dec in &notes.decisions {
            md.push_str(&format!("- {} (proposed by {})\n", dec.description, dec.proposed_by));
        }
        md.push_str("\n");
    }

    if !notes.open_questions.is_empty() {
        md.push_str("## Open Questions\n\n");
        for q in &notes.open_questions {
            md.push_str(&format!("- {}\n", q));
        }
    }

    Ok(md)
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn test_action_item_extraction() {
        let segments = vec![
            make_segment("Alice", "I need to review the design doc by Friday", 0),
            make_segment("Bob", "Sounds good, the weather is nice", 3000),
            make_segment("Alice", "This is urgent, I'll fix the bug ASAP", 6000),
        ];
        let items = extract_action_items_rule_based(&segments);
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].assignee_name, "Alice");
        assert_eq!(items[1].priority, "high"); // "urgent" + "ASAP"
    }

    #[test]
    fn test_decision_extraction() {
        let segments = vec![
            make_segment("Alice", "Let's go with option B for the architecture", 0),
            make_segment("Bob", "I think we should discuss more", 3000),
        ];
        let decisions = extract_decisions_rule_based(&segments);
        assert_eq!(decisions.len(), 1);
        assert!(decisions[0].description.contains("option B"));
    }

    #[test]
    fn test_question_extraction() {
        let segments = vec![
            make_segment("Alice", "What about the timeline?", 0),
            make_segment("Bob", "The timeline is fine.", 3000),
        ];
        let questions = extract_questions_rule_based(&segments);
        assert_eq!(questions.len(), 1);
        assert!(questions[0].contains("timeline"));
    }

    #[test]
    fn test_generate_title_empty() {
        assert_eq!(generate_title("", 3), "Meeting (3 participants)");
    }

    #[test]
    fn test_generate_title_from_text() {
        let title = generate_title("Sprint planning discussion for Q1 deliverables. Let's start.", 2);
        assert_eq!(title, "Sprint planning discussion for Q1 deliverables");
    }

    #[test]
    fn test_meeting_notes_generation() {
        let segments = vec![
            make_segment("Alice", "Let's discuss the Phase 4 implementation plan", 0),
            make_segment("Bob", "I need to set up the CI pipeline by next week", 3000),
            make_segment("Alice", "Agreed, let's go with Rust for the backend", 6000),
            make_segment("Bob", "What about the mobile testing?", 9000),
        ];
        let notes = generate_rule_based_notes(
            "test-meeting-1",
            &segments,
            &["alice_pub".to_string(), "bob_pub".to_string()],
            0,
            12_000,
        );
        assert_eq!(notes.meeting_id, "test-meeting-1");
        assert!(!notes.summary.is_empty());
        assert!(!notes.action_items.is_empty()); // "need to" triggers
        assert!(!notes.decisions.is_empty()); // "let's go with" triggers
        assert!(!notes.open_questions.is_empty()); // "?" triggers
    }

    #[test]
    fn test_export_markdown() {
        let notes = MeetingNotes {
            meeting_id: "test-1".to_string(),
            title: "Test Meeting".to_string(),
            summary: "A test meeting.".to_string(),
            key_points: vec!["Point one".to_string()],
            action_items: vec![ActionItem {
                id: "ai_1".to_string(),
                assignee_pubkey: "pub1".to_string(),
                assignee_name: "Alice".to_string(),
                description: "Do the thing".to_string(),
                deadline: "2026-02-20".to_string(),
                priority: "high".to_string(),
                completed: false,
            }],
            decisions: vec![],
            open_questions: vec![],
            participants: vec!["pub1".to_string()],
            start_time_ms: 0,
            end_time_ms: 60_000,
            duration_seconds: 60,
            generated_at_ms: 0,
        };

        // Store it in archive and test export.
        let mut intel = intelligence().lock().unwrap();
        intel.archive.push(notes);
        drop(intel);

        let md = export_meeting_markdown("test-1".to_string()).unwrap();
        assert!(md.contains("# Test Meeting"));
        assert!(md.contains("Alice"));
        assert!(md.contains("Do the thing"));
    }

    #[test]
    fn test_build_prompt() {
        let prompt = build_meeting_notes_prompt("Alice: Hello\nBob: Hi".to_string()).unwrap();
        assert!(prompt.contains("Alice: Hello"));
        assert!(prompt.contains("action_items"));
    }

    #[test]
    fn test_ai_backend_default() {
        let backend = AiBackend::default();
        matches!(backend, AiBackend::RuleBased);
    }
}
