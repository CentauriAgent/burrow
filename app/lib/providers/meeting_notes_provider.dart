import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/models/meeting_notes.dart';
import 'package:burrow_app/models/transcript.dart';

/// State for meeting notes and history.
class MeetingNotesState {
  /// The most recently generated meeting notes (post-call).
  final MeetingNotes? currentNotes;

  /// Archive of all past meeting notes.
  final List<MeetingNotes> archive;

  /// Whether notes are currently being generated.
  final bool isGenerating;

  /// Search query for history.
  final String searchQuery;

  /// Filtered archive results.
  final List<MeetingNotes> searchResults;

  /// Error message, if any.
  final String? error;

  const MeetingNotesState({
    this.currentNotes,
    this.archive = const [],
    this.isGenerating = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.error,
  });

  MeetingNotesState copyWith({
    MeetingNotes? currentNotes,
    List<MeetingNotes>? archive,
    bool? isGenerating,
    String? searchQuery,
    List<MeetingNotes>? searchResults,
    String? error,
  }) {
    return MeetingNotesState(
      currentNotes: currentNotes ?? this.currentNotes,
      archive: archive ?? this.archive,
      isGenerating: isGenerating ?? this.isGenerating,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      error: error,
    );
  }
}

class MeetingNotesNotifier extends Notifier<MeetingNotesState> {
  @override
  MeetingNotesState build() {
    return const MeetingNotesState();
  }

  /// Generate meeting notes from transcript segments.
  ///
  /// Called after a call ends. Processes the transcript through the
  /// Rust meeting intelligence engine.
  Future<MeetingNotes?> generateNotes({
    required String meetingId,
    required List<TranscriptSegment> segments,
    required List<String> participants,
    required int startTimeMs,
    required int endTimeMs,
  }) async {
    state = state.copyWith(isGenerating: true, error: null);

    try {
      // In production: calls Rust generate_meeting_notes() via FFI.
      // final notesJson = await rust_meeting.generateMeetingNotes(
      //   meetingId: meetingId,
      //   segmentsJson: jsonEncode(segments.map((s) => s.toJson()).toList()),
      //   participantsJson: jsonEncode(participants),
      //   startTimeMs: startTimeMs,
      //   endTimeMs: endTimeMs,
      // );
      // final notes = MeetingNotes.fromJson(jsonDecode(notesJson));

      // For now, create notes from segments directly (mirrors Rust rule-based logic).
      final notes = _generateLocalNotes(
        meetingId: meetingId,
        segments: segments,
        participants: participants,
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
      );

      state = state.copyWith(
        currentNotes: notes,
        archive: [...state.archive, notes],
        isGenerating: false,
      );
      return notes;
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: 'Failed to generate notes: $e',
      );
      return null;
    }
  }

  /// Toggle action item completion.
  void toggleActionItem(String meetingId, String actionItemId) {
    final archiveIdx =
        state.archive.indexWhere((n) => n.meetingId == meetingId);
    if (archiveIdx < 0) return;

    final notes = state.archive[archiveIdx];
    final itemIdx =
        notes.actionItems.indexWhere((a) => a.id == actionItemId);
    if (itemIdx < 0) return;

    notes.actionItems[itemIdx].completed =
        !notes.actionItems[itemIdx].completed;

    final updatedArchive = List<MeetingNotes>.from(state.archive);
    state = state.copyWith(
      archive: updatedArchive,
      currentNotes:
          state.currentNotes?.meetingId == meetingId ? notes : null,
    );
  }

  /// Search meeting history.
  void searchHistory(String query) {
    if (query.isEmpty) {
      state = state.copyWith(searchQuery: '', searchResults: []);
      return;
    }

    final queryLower = query.toLowerCase();
    final results = state.archive.where((n) {
      return n.title.toLowerCase().contains(queryLower) ||
          n.summary.toLowerCase().contains(queryLower) ||
          n.keyPoints.any((p) => p.toLowerCase().contains(queryLower)) ||
          n.actionItems
              .any((a) => a.description.toLowerCase().contains(queryLower));
    }).toList();

    state = state.copyWith(searchQuery: query, searchResults: results);
  }

  /// Get meeting notes by ID.
  MeetingNotes? getNotesById(String meetingId) {
    try {
      return state.archive.firstWhere((n) => n.meetingId == meetingId);
    } catch (_) {
      return null;
    }
  }

  /// Export meeting notes as markdown.
  String exportMarkdown(String meetingId) {
    final notes = getNotesById(meetingId);
    if (notes == null) return '';

    final buffer = StringBuffer();
    buffer.writeln('# ${notes.title}\n');
    buffer.writeln(
        '**Duration:** ${notes.formattedDuration} | **Participants:** ${notes.participants.length}\n');
    buffer.writeln('## Summary\n');
    buffer.writeln('${notes.summary}\n');

    if (notes.keyPoints.isNotEmpty) {
      buffer.writeln('## Key Discussion Points\n');
      for (final point in notes.keyPoints) {
        buffer.writeln('- $point');
      }
      buffer.writeln();
    }

    if (notes.actionItems.isNotEmpty) {
      buffer.writeln('## Action Items\n');
      for (final item in notes.actionItems) {
        final check = item.completed ? 'x' : ' ';
        buffer.writeln(
            '- [$check] **${item.assigneeName}** — ${item.description} (${item.priority})');
      }
      buffer.writeln();
    }

    if (notes.decisions.isNotEmpty) {
      buffer.writeln('## Decisions\n');
      for (final dec in notes.decisions) {
        buffer.writeln('- ${dec.description} (by ${dec.proposedBy})');
      }
      buffer.writeln();
    }

    if (notes.openQuestions.isNotEmpty) {
      buffer.writeln('## Open Questions\n');
      for (final q in notes.openQuestions) {
        buffer.writeln('- $q');
      }
    }

    return buffer.toString();
  }

  /// Local rule-based notes generation (mirrors Rust implementation).
  MeetingNotes _generateLocalNotes({
    required String meetingId,
    required List<TranscriptSegment> segments,
    required List<String> participants,
    required int startTimeMs,
    required int endTimeMs,
  }) {
    final actionKeywords = [
      'action item', 'todo', 'to do', 'need to', 'should',
      'will do', "i'll", 'let me', 'follow up', 'take care of',
    ];
    final decisionKeywords = [
      'decided', 'agreed', "let's go with", "we'll use",
      'the plan is', 'approved',
    ];

    final actionItems = <ActionItem>[];
    final decisions = <Decision>[];
    final questions = <String>[];
    var counter = 0;

    for (final seg in segments) {
      final lower = seg.text.toLowerCase();

      if (actionKeywords.any((kw) => lower.contains(kw))) {
        counter++;
        final priority = lower.contains('urgent') || lower.contains('asap')
            ? 'high'
            : 'medium';
        actionItems.add(ActionItem(
          id: 'ai_$counter',
          assigneePubkey: seg.speakerId,
          assigneeName: seg.speakerName,
          description: seg.text,
          priority: priority,
        ));
      }

      if (decisionKeywords.any((kw) => lower.contains(kw))) {
        decisions.add(Decision(
          description: seg.text,
          proposedBy: seg.speakerName,
        ));
      }

      if (seg.text.contains('?')) {
        questions.add('${seg.speakerName}: ${seg.text}');
      }
    }

    final durationSeconds = (endTimeMs - startTimeMs) ~/ 1000;
    final durationMin = durationSeconds ~/ 60;

    return MeetingNotes(
      meetingId: meetingId,
      title: segments.isNotEmpty
          ? segments.first.text.length > 60
              ? segments.first.text.substring(0, 60)
              : segments.first.text
          : 'Meeting (${participants.length} participants)',
      summary:
          'Meeting with ${participants.length} participant(s), lasting $durationMin minute(s). '
          '${actionItems.length} action item(s) extracted.',
      keyPoints: segments
          .where((s) => s.text.length > 20)
          .take(5)
          .map((s) => s.text.split('.').first.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      actionItems: actionItems,
      decisions: decisions,
      openQuestions: questions,
      participants: participants,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
      durationSeconds: durationSeconds,
      generatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

final meetingNotesProvider =
    NotifierProvider<MeetingNotesNotifier, MeetingNotesState>(() {
  return MeetingNotesNotifier();
});
