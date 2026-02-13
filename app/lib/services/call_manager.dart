/// High-level call manager combining Rust signaling/crypto with Dart WebRTC media.
///
/// Orchestrates the full call flow: session management (Rust) ↔ media (Dart) ↔ signaling (Rust).
library;

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:burrow_app/src/rust/api/call_signaling.dart'
    as rust_signaling;
import 'package:burrow_app/src/rust/api/call_session.dart'
    as rust_session;
import 'package:burrow_app/src/rust/api/call_webrtc.dart'
    as rust_webrtc;
import 'webrtc_service.dart';

/// Manages the full lifecycle of audio/video calls.
class CallManager {
  final WebRtcService _webrtcService = WebRtcService();

  // Stream controllers for UI consumption
  final _callStateController = StreamController<CallStateEvent>.broadcast();
  final _remoteStreamController =
      StreamController<RemoteStreamEvent>.broadcast();
  final _incomingCallController =
      StreamController<IncomingCallEvent>.broadcast();

  /// Emits call state changes (connecting, active, ended, failed).
  Stream<CallStateEvent> get onCallState => _callStateController.stream;

  /// Emits remote media streams.
  Stream<RemoteStreamEvent> get onRemoteStream =>
      _remoteStreamController.stream;

  /// Emits incoming call notifications.
  Stream<IncomingCallEvent> get onIncomingCall =>
      _incomingCallController.stream;

  /// The local media stream for rendering in UI.
  MediaStream? get localStream => _webrtcService.localStream;

  /// Current mute state.
  bool get isMuted => _webrtcService.isMuted;

  /// Current camera state.
  bool get isCameraEnabled => _webrtcService.isCameraEnabled;

  /// Active call ID, if any.
  String? _activeCallId;
  String? get activeCallId => _activeCallId;

  CallManager() {
    // Forward WebRTC events
    _webrtcService.onRemoteStream.listen((event) {
      _remoteStreamController.add(event);
    });

    _webrtcService.onConnectionState.listen((event) {
      _handleConnectionStateChange(event);
    });

    _webrtcService.onIceCandidate.listen((event) {
      _sendIceCandidate(event);
    });
  }

  /// Start an outgoing call.
  ///
  /// Full flow: create session → init media → create offer → signal via Rust.
  Future<String> startCall({
    required String remotePubkeyHex,
    required String localPubkeyHex,
    required String callId,
    bool isVideo = true,
    String? groupIdHex,
  }) async {
    _activeCallId = callId;

    _callStateController.add(CallStateEvent(
      callId: callId,
      state: 'initiating',
    ));

    // 1. Create session in Rust
    await rust_session.createSession(
      callId: callId,
      callType: isVideo ? 'video' : 'audio',
      direction: 'outgoing',
      localPubkeyHex: localPubkeyHex,
      remotePubkeyHex: remotePubkeyHex,
      groupIdHex: groupIdHex,
    );

    // 2. Create peer entry in Rust
    await rust_webrtc.createPeerEntry(
      callId: callId,
      participantPubkeyHex: remotePubkeyHex,
      hasAudioTrack: true,
      hasVideoTrack: isVideo,
    );

    // 3. Initialize local media
    await _webrtcService.initializeWebRTC(isVideo: isVideo);

    // 4. Create peer connection
    await _webrtcService.createBurrowPeerConnection(
      callId: callId,
      remotePubkeyHex: remotePubkeyHex,
    );

    // 5. Create offer
    final offer = await _webrtcService.createOffer(remotePubkeyHex);

    // 6. Send offer via Rust signaling (gift-wrapped)
    final _wrappedEvent = await rust_signaling.initiateCall(
      sdpOffer: offer.sdp!,
      callId: callId,
      callType: isVideo ? 'video' : 'audio',
      recipientPubkeyHex: remotePubkeyHex,
    );

    // TODO: Publish wrappedEvent to Nostr relays

    _callStateController.add(CallStateEvent(
      callId: callId,
      state: 'connecting',
    ));

    await rust_session.updateSessionState(callId: callId, state: 'connecting');

    return callId;
  }

  /// Answer an incoming call.
  ///
  /// Flow: init media → create answer → signal back via Rust.
  Future<void> answerCall({
    required String callId,
    required String callerPubkeyHex,
    required String localPubkeyHex,
    required String remoteSdpOffer,
    bool isVideo = true,
    String? groupIdHex,
  }) async {
    _activeCallId = callId;

    // 1. Create session in Rust (incoming)
    await rust_session.createSession(
      callId: callId,
      callType: isVideo ? 'video' : 'audio',
      direction: 'incoming',
      localPubkeyHex: localPubkeyHex,
      remotePubkeyHex: callerPubkeyHex,
      groupIdHex: groupIdHex,
    );

    // 2. Create peer entry
    await rust_webrtc.createPeerEntry(
      callId: callId,
      participantPubkeyHex: callerPubkeyHex,
      hasAudioTrack: true,
      hasVideoTrack: isVideo,
    );

    // 3. Initialize local media
    await _webrtcService.initializeWebRTC(isVideo: isVideo);

    // 4. Create peer connection
    await _webrtcService.createBurrowPeerConnection(
      callId: callId,
      remotePubkeyHex: callerPubkeyHex,
    );

    // 5. Create answer from remote offer
    final remoteOffer = RTCSessionDescription(remoteSdpOffer, 'offer');
    final answer =
        await _webrtcService.createAnswer(callerPubkeyHex, remoteOffer);

    // 6. Send answer via Rust signaling
    final _wrappedEvent = await rust_signaling.acceptCall(
      sdpAnswer: answer.sdp!,
      callId: callId,
      callerPubkeyHex: callerPubkeyHex,
    );

    // TODO: Publish wrappedEvent to Nostr relays

    _callStateController.add(CallStateEvent(
      callId: callId,
      state: 'connecting',
    ));

    await rust_session.updateSessionState(callId: callId, state: 'connecting');
  }

  /// End an active call.
  ///
  /// Flow: signal hangup → stop media → cleanup state.
  Future<void> endCall(String callId) async {
    if (_activeCallId != callId) return;

    _callStateController.add(CallStateEvent(
      callId: callId,
      state: 'ending',
    ));

    // Get session to find remote pubkey
    final session = await rust_session.getSession(callId: callId);
    if (session != null) {
      // Signal hangup via Rust
      final _wrappedEvent = await rust_signaling.endCall(
        callId: callId,
        remotePubkeyHex: session.remotePubkeyHex,
      );
      // TODO: Publish wrappedEvent to Nostr relays

      await rust_session.updateSessionState(callId: callId, state: 'ending');
    }

    // Cleanup WebRTC
    await _webrtcService.dispose();

    // Cleanup Rust state
    await rust_webrtc.removeCallPeers(callId: callId);
    await rust_session.removeSession(callId: callId);

    _activeCallId = null;

    _callStateController.add(CallStateEvent(
      callId: callId,
      state: 'ended',
    ));
  }

  /// Handle an incoming signaling event (called when a gift-wrapped event is received).
  Future<void> handleSignalingEvent(
      rust_signaling.CallSignalingEvent event) async {
    switch (event.kind) {
      case 25050: // Call offer
        _incomingCallController.add(IncomingCallEvent(
          callId: event.callId,
          callerPubkeyHex: event.senderPubkeyHex,
          callType: event.callType ?? 'audio',
          sdpOffer: event.content,
        ));
        break;

      case 25051: // Call answer
        // Set remote description on peer connection
        final answerSdp = RTCSessionDescription(event.content, 'answer');
        await _webrtcService.setRemoteDescription(
          event.senderPubkeyHex,
          answerSdp,
        );
        break;

      case 25052: // ICE candidate
        // Parse and add ICE candidate
        // Content is JSON with candidate, sdpMid, sdpMLineIndex
        // (parsing delegated to caller for simplicity)
        break;

      case 25053: // Call end
        if (_activeCallId == event.callId) {
          await endCall(event.callId);
        }
        break;
    }
  }

  /// Toggle mute and signal state change to remote peer.
  Future<bool> toggleMute() async {
    final muted = _webrtcService.toggleMute();
    if (_activeCallId != null) {
      await rust_session.setMuted(callId: _activeCallId!, muted: muted);
    }
    return muted;
  }

  /// Toggle camera and signal state change.
  Future<bool> toggleCamera() async {
    final enabled = _webrtcService.toggleCamera();
    if (_activeCallId != null) {
      await rust_session.setVideoEnabled(
          callId: _activeCallId!, enabled: enabled);
    }
    return enabled;
  }

  /// Switch between front/back camera.
  Future<void> switchCamera() => _webrtcService.switchCamera();

  // ── Private helpers ──────────────────────────────────────────────────────

  void _handleConnectionStateChange(PeerConnectionStateEvent event) {
    final callId = _activeCallId;
    if (callId == null) return;

    String stateStr;
    switch (event.state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        stateStr = 'new';
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        stateStr = 'checking';
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        stateStr = 'connected';
        _callStateController
            .add(CallStateEvent(callId: callId, state: 'active'));
        rust_session.updateSessionState(callId: callId, state: 'active');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        stateStr = 'disconnected';
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        stateStr = 'failed';
        _callStateController
            .add(CallStateEvent(callId: callId, state: 'failed'));
        rust_session.updateSessionState(callId: callId, state: 'failed');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        stateStr = 'closed';
        break;
    }

    // Update peer state in Rust
    rust_webrtc.updatePeerState(
      callId: callId,
      participantPubkeyHex: event.remotePubkeyHex,
      state: stateStr,
    );
  }

  Future<void> _sendIceCandidate(IceCandidateEvent event) async {
    final callId = _activeCallId;
    if (callId == null) return;

    final _wrappedEvent = await rust_signaling.sendIceCandidate(
      candidate: event.candidate.candidate!,
      sdpMid: event.candidate.sdpMid,
      sdpMLineIndex:
          event.candidate.sdpMLineIndex != null
              ? event.candidate.sdpMLineIndex!
              : null,
      callId: callId,
      remotePubkeyHex: event.remotePubkeyHex,
    );
    // TODO: Publish wrappedEvent to Nostr relays
  }

  /// Dispose the call manager and release all resources.
  Future<void> dispose() async {
    if (_activeCallId != null) {
      await endCall(_activeCallId!);
    }
    await _callStateController.close();
    await _remoteStreamController.close();
    await _incomingCallController.close();
  }
}

// ── Event types ──────────────────────────────────────────────────────────

class CallStateEvent {
  final String callId;
  final String state; // initiating, connecting, active, ending, ended, failed

  CallStateEvent({required this.callId, required this.state});
}

class IncomingCallEvent {
  final String callId;
  final String callerPubkeyHex;
  final String callType;
  final String sdpOffer;

  IncomingCallEvent({
    required this.callId,
    required this.callerPubkeyHex,
    required this.callType,
    required this.sdpOffer,
  });
}
