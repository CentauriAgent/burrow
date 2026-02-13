import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/models/meeting_notes.dart';

void main() {
  group('ActionItem', () {
    test('fromJson creates valid action item', () {
      final json = {
        'id': 'ai_1',
        'assignee_pubkey': 'pub123',
        'assignee_name': 'Alice',
        'description': 'Review the design doc',
        'deadline': '2026-02-20',
        'priority': 'high',
        'completed': false,
      };

      final item = ActionItem.fromJson(json);
      expect(item.id, 'ai_1');
      expect(item.assigneeName, 'Alice');
      expect(item.description, 'Review the design doc');
      expect(item.isHighPriority, true);
      expect(item.completed, false);
    });

    test('toggle completion', () {
      final item = ActionItem(
        id: 'ai_2',
        description: 'Test action',
      );
      expect(item.completed, false);
      item.completed = true;
      expect(item.completed, true);
    });
  });

  group('Decision', () {
    test('fromJson creates valid decision', () {
      final dec = Decision.fromJson({
        'description': 'Go with option B',
        'proposed_by': 'Bob',
        'context': 'Architecture discussion',
      });
      expect(dec.description, 'Go with option B');
      expect(dec.proposedBy, 'Bob');
    });
  });

  group('MeetingNotes', () {
    test('fromJson creates complete notes', () {
      final json = {
        'meeting_id': 'mtg_001',
        'title': 'Sprint Planning',
        'summary': 'Discussed next sprint goals.',
        'key_points': ['Point A', 'Point B'],
        'action_items': [
          {
            'id': 'ai_1',
            'assignee_name': 'Alice',
            'description': 'Write tests',
            'priority': 'high',
            'completed': false,
          },
          {
            'id': 'ai_2',
            'assignee_name': 'Bob',
            'description': 'Update docs',
            'priority': 'medium',
            'completed': true,
          },
        ],
        'decisions': [],
        'open_questions': ['What about the timeline?'],
        'participants': ['pub1', 'pub2'],
        'start_time_ms': 1000000,
        'end_time_ms': 1060000,
        'duration_seconds': 60,
        'generated_at_ms': 1060000,
      };

      final notes = MeetingNotes.fromJson(json);
      expect(notes.meetingId, 'mtg_001');
      expect(notes.title, 'Sprint Planning');
      expect(notes.keyPoints.length, 2);
      expect(notes.actionItems.length, 2);
      expect(notes.pendingActionItems, 1);
      expect(notes.openQuestions.length, 1);
    });

    test('formattedDuration for short meetings', () {
      const notes = MeetingNotes(
        meetingId: 'test',
        title: 'Test',
        summary: '',
        durationSeconds: 300,
      );
      expect(notes.formattedDuration, '5m');
    });

    test('formattedDuration for long meetings', () {
      const notes = MeetingNotes(
        meetingId: 'test',
        title: 'Test',
        summary: '',
        durationSeconds: 5400,
      );
      expect(notes.formattedDuration, '1h 30m');
    });

    test('pendingActionItems counts correctly', () {
      final notes = MeetingNotes(
        meetingId: 'test',
        title: 'Test',
        summary: '',
        actionItems: [
          ActionItem(id: '1', description: 'a', completed: false),
          ActionItem(id: '2', description: 'b', completed: true),
          ActionItem(id: '3', description: 'c', completed: false),
        ],
      );
      expect(notes.pendingActionItems, 2);
    });

    test('fromJson handles empty/missing fields', () {
      final notes = MeetingNotes.fromJson({});
      expect(notes.meetingId, '');
      expect(notes.title, 'Meeting');
      expect(notes.actionItems, isEmpty);
      expect(notes.keyPoints, isEmpty);
    });
  });
}
