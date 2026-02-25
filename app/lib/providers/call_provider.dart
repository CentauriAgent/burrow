import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:burrow_app/services/call_manager.dart';
import 'package:burrow_app/services/webrtc_service.dart';

/// Call state exposed to UI.
enum CallStatus {
  idle,
  incoming,
  outgoing,
  connecting,
  active,
  ending,
  ended,
  failed,
}

class CallState {
  final CallStatus status;
  final String? callId;
  final String? remotePubkeyHex;
  final String? remoteName;
  final String? remoteAvatarUrl;
  final String callType; // 'audio' or 'video'
  final bool isMuted;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool controlsVisible;
  final MediaStream? localStream;
  final MediaStream? remoteStream;
  final String? sdpOffer; // for incoming calls
  final DateTime? callStartTime;
  final Duration? callDuration;
  final String? connectionQuality; // 'excellent', 'good', 'poor'

  const CallState({
    this.status = CallStatus.idle,
    this.callId,
    this.remotePubkeyHex,
    this.remoteName,
    this.remoteAvatarUrl,
    this.callType = 'audio',
    this.isMuted = false,
    this.isCameraEnabled = true,
    this.isSpeakerOn = false,
    this.controlsVisible = true,
    this.localStream,
    this.remoteStream,
    this.sdpOffer,
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
    String? remoteAvatarUrl,
    String? callType,
    bool? isMuted,
    bool? isCameraEnabled,
    bool? isSpeakerOn,
    bool? controlsVisible,
    MediaStream? localStream,
    MediaStream? remoteStream,
    String? sdpOffer,
    DateTime? callStartTime,
    Duration? callDuration,
    String? connectionQuality,
  }) {
    return CallState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      remotePubkeyHex: remotePubkeyHex ?? this.remotePubkeyHex,
      remoteName: remoteName ?? this.remoteName,
      remoteAvatarUrl: remoteAvatarUrl ?? this.remoteAvatarUrl,
      callType: callType ?? this.callType,
      isMuted: isMuted ?? this.isMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      localStream: localStream ?? this.localStream,
      remoteStream: remoteStream ?? this.remoteStream,
      sdpOffer: sdpOffer ?? this.sdpOffer,
      callStartTime: callStartTime ?? this.callStartTime,
      callDuration: callDuration ?? this.callDuration,
      connectionQuality: connectionQuality ?? this.connectionQuality,
    );
  }
}

class CallNotifier extends Notifier<CallState> {
  late final CallManager _callManager;
  final List<StreamSubscription> _subscriptions = [];
  Timer? _durationTimer;
  Timer? _controlsHideTimer;

  @override
  CallState build() {
    _callManager = CallManager();

    _subscriptions.add(_callManager.onCallState.listen(_handleCallState));
    _subscriptions.add(_callManager.onRemoteStream.listen(_handleRemoteStream));
    _subscriptions.add(_callManager.onIncomingCall.listen(_handleIncomingCall));

    // Start listening for incoming call events from Nostr relays
    _callManager.startListening();

    ref.onDispose(() {
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _durationTimer?.cancel();
      _controlsHideTimer?.cancel();
      _callManager.dispose();
    });

    return const CallState();
  }

  void _handleCallState(CallStateEvent event) {
    switch (event.state) {
      case 'initiating':
      case 'connecting':
        state = state.copyWith(status: CallStatus.connecting);
        break;
      case 'active':
        final now = DateTime.now();
        // Video calls default to speaker on
        final useSpeaker = state.callType == 'video';
        state = state.copyWith(
          status: CallStatus.active,
          callStartTime: now,
          isSpeakerOn: useSpeaker,
        );
        Helper.setSpeakerphoneOn(useSpeaker);
        _startDurationTimer();
        _scheduleControlsHide();
        break;
      case 'ending':
        state = state.copyWith(status: CallStatus.ending);
        break;
      case 'ended':
        _durationTimer?.cancel();
        state = state.copyWith(status: CallStatus.ended);
        break;
      case 'failed':
        _durationTimer?.cancel();
        state = state.copyWith(status: CallStatus.failed);
        break;
    }
  }

  void _handleRemoteStream(RemoteStreamEvent event) {
    if (event.isAdded) {
      state = state.copyWith(remoteStream: event.stream);
    }
  }

  void _handleIncomingCall(IncomingCallEvent event) {
    state = state.copyWith(
      status: CallStatus.incoming,
      callId: event.callId,
      remotePubkeyHex: event.callerPubkeyHex,
      remoteName: _truncatePubkey(event.callerPubkeyHex),
      callType: event.callType,
      sdpOffer: event.sdpOffer,
    );
  }

  /// Start an outgoing call.
  Future<void> startCall({
    required String remotePubkeyHex,
    required String localPubkeyHex,
    required String callId,
    bool isVideo = true,
    String? remoteName,
  }) async {
    state = CallState(
      status: CallStatus.outgoing,
      callId: callId,
      remotePubkeyHex: remotePubkeyHex,
      remoteName: remoteName ?? _truncatePubkey(remotePubkeyHex),
      callType: isVideo ? 'video' : 'audio',
    );

    await _callManager.startCall(
      remotePubkeyHex: remotePubkeyHex,
      localPubkeyHex: localPubkeyHex,
      callId: callId,
      isVideo: isVideo,
    );

    state = state.copyWith(localStream: _callManager.localStream);
  }

  /// Accept an incoming call.
  Future<void> acceptCall({required String localPubkeyHex}) async {
    final callId = state.callId;
    final remotePubkey = state.remotePubkeyHex;
    final sdpOffer = state.sdpOffer;
    if (callId == null || remotePubkey == null || sdpOffer == null) return;

    state = state.copyWith(status: CallStatus.connecting);

    await _callManager.answerCall(
      callId: callId,
      callerPubkeyHex: remotePubkey,
      localPubkeyHex: localPubkeyHex,
      remoteSdpOffer: sdpOffer,
      isVideo: state.isVideo,
    );

    state = state.copyWith(localStream: _callManager.localStream);
  }

  /// Reject an incoming call or cancel outgoing.
  Future<void> rejectCall() async {
    final callId = state.callId;
    if (callId != null) {
      await _callManager.endCall(callId);
    }
    state = const CallState();
  }

  /// End active call.
  Future<void> endCall() async {
    final callId = state.callId;
    if (callId != null) {
      await _callManager.endCall(callId);
    }
    state = const CallState();
  }

  /// Toggle mute.
  Future<void> toggleMute() async {
    final muted = await _callManager.toggleMute();
    state = state.copyWith(isMuted: muted);
  }

  /// Toggle camera.
  Future<void> toggleCamera() async {
    final enabled = await _callManager.toggleCamera();
    state = state.copyWith(isCameraEnabled: enabled);
  }

  /// Switch front/back camera.
  Future<void> switchCamera() async {
    await _callManager.switchCamera();
  }

  /// Toggle speaker output (earpiece ↔ speaker).
  Future<void> toggleSpeaker() async {
    final newValue = !state.isSpeakerOn;
    state = state.copyWith(isSpeakerOn: newValue);
    try {
      await Helper.setSpeakerphoneOn(newValue);
    } catch (e) {
      // If routing fails, revert state
      state = state.copyWith(isSpeakerOn: !newValue);
    }
  }

  /// Show controls (and auto-hide after 3s during active call).
  void showControls() {
    state = state.copyWith(controlsVisible: true);
    if (state.status == CallStatus.active) {
      _scheduleControlsHide();
    }
  }

  /// Hide controls.
  void hideControls() {
    state = state.copyWith(controlsVisible: false);
  }

  /// Toggle controls visibility.
  void toggleControls() {
    if (state.controlsVisible) {
      hideControls();
    } else {
      showControls();
    }
  }

  /// Reset to idle after viewing call ended screen.
  void dismiss() {
    state = const CallState();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.callStartTime != null) {
        state = state.copyWith(
          callDuration: DateTime.now().difference(state.callStartTime!),
        );
      }
    });
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (state.status == CallStatus.active) {
        state = state.copyWith(controlsVisible: false);
      }
    });
  }

  String _truncatePubkey(String hex) {
    if (hex.length <= 12) return hex;
    return '${hex.substring(0, 6)}...${hex.substring(hex.length - 6)}';
  }
}

final callProvider = NotifierProvider<CallNotifier, CallState>(() {
  return CallNotifier();
});
