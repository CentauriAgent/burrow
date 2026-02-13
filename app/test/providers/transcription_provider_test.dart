import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/transcription_provider.dart';
import 'package:burrow_app/services/transcription_service.dart';

void main() {
  group('TranscriptionState', () {
    test('default state is idle', () {
      const state = TranscriptionState();
      expect(state.status, TranscriptionStatus.idle);
      expect(state.segments, isEmpty);
      expect(state.callId, isNull);
      expect(state.showLiveTranscript, true);
      expect(state.isActive, false);
      expect(state.isPaused, false);
    });

    test('copyWith preserves unmodified fields', () {
      const state = TranscriptionState(
        status: TranscriptionStatus.transcribing,
        callId: 'call-123',
        showLiveTranscript: true,
      );

      final updated = state.copyWith(showLiveTranscript: false);
      expect(updated.status, TranscriptionStatus.transcribing);
      expect(updated.callId, 'call-123');
      expect(updated.showLiveTranscript, false);
    });

    test('isActive and isPaused reflect status', () {
      const active = TranscriptionState(
        status: TranscriptionStatus.transcribing,
      );
      expect(active.isActive, true);
      expect(active.isPaused, false);

      const paused = TranscriptionState(
        status: TranscriptionStatus.paused,
      );
      expect(paused.isActive, false);
      expect(paused.isPaused, true);
    });
  });

  group('TranscriptionService', () {
    test('initializes and changes status', () async {
      final service = TranscriptionService();
      expect(service.status, TranscriptionStatus.idle);

      final statuses = <TranscriptionStatus>[];
      service.onStatus.listen(statuses.add);

      await service.initialize();
      expect(service.status, TranscriptionStatus.ready);

      service.dispose();
    });

    test('search returns empty for no segments', () {
      final service = TranscriptionService();
      expect(service.search('test'), isEmpty);
      service.dispose();
    });

    test('getFormattedTranscript returns empty for no segments', () {
      final service = TranscriptionService();
      expect(service.getFormattedTranscript(), isEmpty);
      service.dispose();
    });
  });
}
