/// Pure Dart unit tests for call state models.
/// These test the data structures without depending on Rust FFI bindings.
import 'package:flutter_test/flutter_test.dart';

// Inline copies of CallStatus and CallState for testing without FFI dependencies.
// These mirror the types in providers/call_provider.dart.

enum CallStatus {
  idle, incoming, outgoing, connecting, active, ending, ended, failed,
}

class CallState {
  final CallStatus status;
  final String? callId;
  final String? remotePubkeyHex;
  final String? remoteName;
  final String callType;
  final bool isMuted;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool controlsVisible;
  final DateTime? callStartTime;
  final Duration? callDuration;
  final String? connectionQuality;

  const CallState({
    this.status = CallStatus.idle,
    this.callId,
    this.remotePubkeyHex,
    this.remoteName,
    this.callType = 'audio',
    this.isMuted = false,
    this.isCameraEnabled = true,
    this.isSpeakerOn = false,
    this.controlsVisible = true,
    this.callStartTime,
    this.callDuration,
    this.connectionQuality,
  });

  bool get isVideo => callType == 'video';

  CallState copyWith({
    CallStatus? status,
    String? callId,
    String? remotePubkeyHex,
    String? remoteName,
    String? callType,
    bool? isMuted,
    bool? isCameraEnabled,
    bool? isSpeakerOn,
    bool? controlsVisible,
    DateTime? callStartTime,
    Duration? callDuration,
    String? connectionQuality,
  }) {
    return CallState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      remotePubkeyHex: remotePubkeyHex ?? this.remotePubkeyHex,
      remoteName: remoteName ?? this.remoteName,
      callType: callType ?? this.callType,
      isMuted: isMuted ?? this.isMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      callStartTime: callStartTime ?? this.callStartTime,
      callDuration: callDuration ?? this.callDuration,
      connectionQuality: connectionQuality ?? this.connectionQuality,
    );
  }
}

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

    test('call state flow: idle → outgoing → connecting → active → ended', () {
      var state = const CallState();
      expect(state.status, CallStatus.idle);

      state = state.copyWith(
        status: CallStatus.outgoing,
        callId: 'flow-test',
        remotePubkeyHex: 'abc123',
        callType: 'audio',
      );
      expect(state.status, CallStatus.outgoing);

      state = state.copyWith(status: CallStatus.connecting);
      expect(state.status, CallStatus.connecting);

      final startTime = DateTime.now();
      state = state.copyWith(
        status: CallStatus.active,
        callStartTime: startTime,
      );
      expect(state.status, CallStatus.active);
      expect(state.callStartTime, startTime);

      state = state.copyWith(
        status: CallStatus.ended,
        callDuration: const Duration(minutes: 2),
      );
      expect(state.status, CallStatus.ended);
      expect(state.callDuration!.inMinutes, 2);
    });

    test('mute toggle', () {
      var state = const CallState(status: CallStatus.active);
      expect(state.isMuted, false);

      state = state.copyWith(isMuted: true);
      expect(state.isMuted, true);

      state = state.copyWith(isMuted: false);
      expect(state.isMuted, false);
    });

    test('camera toggle', () {
      var state = const CallState(status: CallStatus.active, callType: 'video');
      expect(state.isCameraEnabled, true);

      state = state.copyWith(isCameraEnabled: false);
      expect(state.isCameraEnabled, false);
    });

    test('connection quality values', () {
      const state = CallState(connectionQuality: 'excellent');
      expect(state.connectionQuality, 'excellent');

      final updated = state.copyWith(connectionQuality: 'poor');
      expect(updated.connectionQuality, 'poor');
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
