import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/call_provider.dart';

void main() {
  group('CallState', () {
    test('default state is idle', () {
      const state = CallState();
      expect(state.status, CallStatus.idle);
      expect(state.callId, isNull);
      expect(state.remotePubkeyHex, isNull);
      expect(state.callType, 'audio');
      expect(state.isMuted, false);
      expect(state.isCameraEnabled, true);
      expect(state.isSpeakerOn, false);
      expect(state.controlsVisible, true);
      expect(state.isVideo, false);
    });

    test('isVideo returns true for video call type', () {
      const state = CallState(callType: 'video');
      expect(state.isVideo, true);
    });

    test('isVideo returns false for audio call type', () {
      const state = CallState(callType: 'audio');
      expect(state.isVideo, false);
    });

    test('copyWith preserves unmodified fields', () {
      const original = CallState(
        status: CallStatus.active,
        callId: 'test-123',
        remotePubkeyHex: 'aabbccdd',
        callType: 'video',
        isMuted: true,
      );

      final modified = original.copyWith(isMuted: false);
      expect(modified.status, CallStatus.active);
      expect(modified.callId, 'test-123');
      expect(modified.remotePubkeyHex, 'aabbccdd');
      expect(modified.callType, 'video');
      expect(modified.isMuted, false);
    });

    test('copyWith replaces specified fields', () {
      const original = CallState();
      final modified = original.copyWith(
        status: CallStatus.incoming,
        callId: 'call-456',
        remotePubkeyHex: 'deadbeef',
        callType: 'video',
      );

      expect(modified.status, CallStatus.incoming);
      expect(modified.callId, 'call-456');
      expect(modified.remotePubkeyHex, 'deadbeef');
      expect(modified.isVideo, true);
    });

    test('copyWith with callDuration', () {
      const original = CallState(status: CallStatus.active);
      final modified = original.copyWith(
        callDuration: const Duration(minutes: 5, seconds: 30),
      );
      expect(modified.callDuration, const Duration(minutes: 5, seconds: 30));
    });
  });

  group('CallStatus', () {
    test('all statuses exist', () {
      expect(CallStatus.values, hasLength(8));
      expect(CallStatus.values, contains(CallStatus.idle));
      expect(CallStatus.values, contains(CallStatus.incoming));
      expect(CallStatus.values, contains(CallStatus.outgoing));
      expect(CallStatus.values, contains(CallStatus.connecting));
      expect(CallStatus.values, contains(CallStatus.active));
      expect(CallStatus.values, contains(CallStatus.ending));
      expect(CallStatus.values, contains(CallStatus.ended));
      expect(CallStatus.values, contains(CallStatus.failed));
    });
  });
}
