import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/meeting_notes_provider.dart';

void main() {
  group('MeetingNotesState', () {
    test('default state', () {
      const state = MeetingNotesState();
      expect(state.currentNotes, isNull);
      expect(state.archive, isEmpty);
      expect(state.isGenerating, false);
      expect(state.searchQuery, '');
      expect(state.error, isNull);
    });

    test('copyWith preserves fields', () {
      const state = MeetingNotesState(isGenerating: true);
      final updated = state.copyWith(searchQuery: 'test');
      expect(updated.isGenerating, true);
      expect(updated.searchQuery, 'test');
    });
  });
}
