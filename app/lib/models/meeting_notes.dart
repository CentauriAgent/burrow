/// Data models for AI-generated meeting notes.
library;

/// An extracted action item.
class ActionItem {
  final String id;
  final String assigneePubkey;
  final String assigneeName;
  final String description;
  final String deadline;
  final String priority;
  bool completed;

  ActionItem({
    required this.id,
    this.assigneePubkey = '',
    this.assigneeName = '',
    required this.description,
    this.deadline = '',
    this.priority = 'medium',
    this.completed = false,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      id: json['id'] as String? ?? '',
      assigneePubkey: json['assignee_pubkey'] as String? ?? '',
      assigneeName: json['assignee_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      deadline: json['deadline'] as String? ?? '',
      priority: json['priority'] as String? ?? 'medium',
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'assignee_pubkey': assigneePubkey,
        'assignee_name': assigneeName,
        'description': description,
        'deadline': deadline,
        'priority': priority,
        'completed': completed,
      };

  bool get isHighPriority => priority == 'high';
}

/// A key decision from the meeting.
class Decision {
  final String description;
  final String proposedBy;
  final String context;

  const Decision({
    required this.description,
    this.proposedBy = '',
    this.context = '',
  });

  factory Decision.fromJson(Map<String, dynamic> json) {
    return Decision(
      description: json['description'] as String? ?? '',
      proposedBy: json['proposed_by'] as String? ?? '',
      context: json['context'] as String? ?? '',
    );
  }
}

/// Complete meeting notes.
class MeetingNotes {
  final String meetingId;
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<ActionItem> actionItems;
  final List<Decision> decisions;
  final List<String> openQuestions;
  final List<String> participants;
  final int startTimeMs;
  final int endTimeMs;
  final int durationSeconds;
  final int generatedAtMs;

  const MeetingNotes({
    required this.meetingId,
    required this.title,
    required this.summary,
    this.keyPoints = const [],
    this.actionItems = const [],
    this.decisions = const [],
    this.openQuestions = const [],
    this.participants = const [],
    this.startTimeMs = 0,
    this.endTimeMs = 0,
    this.durationSeconds = 0,
    this.generatedAtMs = 0,
  });

  factory MeetingNotes.fromJson(Map<String, dynamic> json) {
    return MeetingNotes(
      meetingId: json['meeting_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Meeting',
      summary: json['summary'] as String? ?? '',
      keyPoints: (json['key_points'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      actionItems: (json['action_items'] as List<dynamic>?)
              ?.map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      decisions: (json['decisions'] as List<dynamic>?)
              ?.map((e) => Decision.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      openQuestions: (json['open_questions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      participants: (json['participants'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      startTimeMs: (json['start_time_ms'] as num?)?.toInt() ?? 0,
      endTimeMs: (json['end_time_ms'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      generatedAtMs: (json['generated_at_ms'] as num?)?.toInt() ?? 0,
    );
  }

  /// Duration formatted as "Xm" or "Xh Ym".
  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  /// Count of pending (uncompleted) action items.
  int get pendingActionItems =>
      actionItems.where((a) => !a.completed).length;
}
