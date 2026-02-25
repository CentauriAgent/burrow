/// High-level call manager combining Rust signaling/crypto with Dart WebRTC media.
///
/// Orchestrates the full call flow: session management (Rust) ↔ media (Dart) ↔ signaling (Rust+Nostr).
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:burrow_app/src/rust/api/call_signaling.dart' as rust_signaling;
import 'package:burrow_app/src/rust/api/call_session.dart' as rust_session;
import 'package:burrow_app/src/rust/api/call_webrtc.dart' as rust_webrtc;
import 'nostr_signaling_service.dart';
import 'webrtc_service.dart';

class CallManager {
  final WebRtcService _webrtcService = WebRtcService();
  final NostrSignalingService _signalingService = NostrSignalingService();
  StreamSubscription? _signalingSubscription;

  final _callStateController = StreamController<CallStateEvent>.broadcast();
  final _remoteStreamController =
      StreamController<RemoteStreamEvent>.broadcast();
  final _incomingCallController =
      StreamController<IncomingCallEvent>.broadcast();

  Stream<CallStateEvent> get onCallState => _callStateController.stream;
  Stream<RemoteStreamEvent> get onRemoteStream =>
      _remoteStreamController.stream;
  Stream<IncomingCallEvent> get onIncomingCall =>
      _incomingCallController.stream;

  MediaStream? get localStream => _webrtcService.localStream;
  bool get isMuted => _webrtcService.isMuted;
  bool get isCameraEnabled => _webrtcService.isCameraEnabled;

  String? _activeCallId;
  String? get activeCallId => _activeCallId;

  String? _remotePubkeyHex;

  CallManager() {
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

  /// Start listening for incoming call events from Nostr relays.
  Future<void> startListening() async {
    await _signalingService.startListening();
    _signalingSubscription = _signalingService.onSignalingEvent.listen(
      (event) => handleSignalingEvent(event),
    );
  }

  /// Stop listening for incoming call events.
  Future<void> stopListening() async {
    await _signalingSubscription?.cancel();
    _signalingSubscription = null;
    await _signalingService.stopListening();
  }

  /// Start an outgoing call.
  Future<String> startCall({
    required String remotePubkeyHex,
    required String localPubkeyHex,
    required String callId,
    bool isVideo = true,
    String? groupIdHex,
  }) async {
    _activeCallId = callId;
    _remotePubkeyHex = remotePubkeyHex;

    _callStateController.add(
      CallStateEvent(callId: callId, state: 'initiating'),
    );

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

    // 6. Send offer via Rust signaling (gift-wrapped) and publish to relays
    final wrappedEventJson = await rust_signaling.initiateCall(
      sdpOffer: offer.sdp!,
      callId: callId,
      callType: isVideo ? 'video' : 'audio',
      recipientPubkeyHex: remotePubkeyHex,
    );
    await _signalingService.publishSignalingEvent(wrappedEventJson);

    _callStateController.add(
      CallStateEvent(callId: callId, state: 'connecting'),
    );

    await rust_session.updateSessionState(callId: callId, state: 'connecting');
    return callId;
  }

  /// Answer an incoming call.
  Future<void> answerCall({
    required String callId,
    required String callerPubkeyHex,
    required String localPubkeyHex,
    required String remoteSdpOffer,
    bool isVideo = true,
    String? groupIdHex,
  }) async {
    _activeCallId = callId;
    _remotePubkeyHex = callerPubkeyHex;

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
    final answer = await _webrtcService.createAnswer(
      callerPubkeyHex,
      remoteOffer,
    );

    // 6. Send answer via Rust signaling and publish to relays
    final wrappedEventJson = await rust_signaling.acceptCall(
      sdpAnswer: answer.sdp!,
      callId: callId,
      callerPubkeyHex: callerPubkeyHex,
    );
    await _signalingService.publishSignalingEvent(wrappedEventJson);

    _callStateController.add(
      CallStateEvent(callId: callId, state: 'connecting'),
    );

    await rust_session.updateSessionState(callId: callId, state: 'connecting');
  }

  /// End an active call.
  Future<void> endCall(String callId) async {
    if (_activeCallId != callId) return;

    _callStateController.add(CallStateEvent(callId: callId, state: 'ending'));

    // Try to send hangup signal, but don't block cleanup on failure
    try {
      final session = await rust_session.getSession(callId: callId);
      if (session != null) {
        final wrappedEventJson = await rust_signaling.endCall(
          callId: callId,
          remotePubkeyHex: session.remotePubkeyHex,
        );
        await _signalingService.publishSignalingEvent(wrappedEventJson);
        await rust_session.updateSessionState(callId: callId, state: 'ending');
      }
    } catch (_) {
      // Signaling may fail if not connected — still clean up
    }

    try {
      await _webrtcService.dispose();
    } catch (_) {}
    try {
      await rust_webrtc.removeCallPeers(callId: callId);
    } catch (_) {}
    try {
      await rust_session.removeSession(callId: callId);
    } catch (_) {}

    _activeCallId = null;
    _remotePubkeyHex = null;

    _callStateController.add(CallStateEvent(callId: callId, state: 'ended'));
  }

  /// Handle an incoming signaling event from the Rust stream.
  Future<void> handleSignalingEvent(
    rust_signaling.CallSignalingEvent event,
  ) async {
    switch (event.kind) {
      case 25050: // Call offer
        // Parse the SDP from content JSON
        String sdpOffer;
        try {
          final payload = jsonDecode(event.content) as Map<String, dynamic>;
          sdpOffer = payload['sdp'] as String;
        } catch (_) {
          sdpOffer = event.content;
        }
        _incomingCallController.add(
          IncomingCallEvent(
            callId: event.callId,
            callerPubkeyHex: event.senderPubkeyHex,
            callType: event.callType ?? 'audio',
            sdpOffer: sdpOffer,
          ),
        );

      case 25051: // Call answer
        String sdpAnswer;
        try {
          final payload = jsonDecode(event.content) as Map<String, dynamic>;
          sdpAnswer = payload['sdp'] as String;
        } catch (_) {
          sdpAnswer = event.content;
        }
        final answerDesc = RTCSessionDescription(sdpAnswer, 'answer');
        await _webrtcService.setRemoteDescription(
          event.senderPubkeyHex,
          answerDesc,
        );

      case 25052: // ICE candidate
        try {
          final payload = jsonDecode(event.content) as Map<String, dynamic>;
          final candidate = RTCIceCandidate(
            payload['candidate'] as String,
            payload['sdp_mid'] as String?,
            payload['sdp_m_line_index'] as int?,
          );
          await _webrtcService.addIceCandidate(
            event.senderPubkeyHex,
            candidate,
          );
        } catch (_) {
          // Malformed ICE candidate — skip
        }

      case 25053: // Call end
        if (_activeCallId == event.callId) {
          await endCall(event.callId);
        }

      case 25054: // Call state update (mute/camera)
        // Forward to UI via call state
        break;
    }
  }

  /// Toggle mute and signal state change to remote peer.
  Future<bool> toggleMute() async {
    final muted = _webrtcService.toggleMute();
    if (_activeCallId != null) {
      await rust_session.setMuted(callId: _activeCallId!, muted: muted);
      // Signal state update to remote
      if (_remotePubkeyHex != null) {
        try {
          final wrappedJson = await rust_signaling.sendCallStateUpdate(
            callId: _activeCallId!,
            remotePubkeyHex: _remotePubkeyHex!,
            isMuted: muted,
            isVideoEnabled: null,
          );
          await _signalingService.publishSignalingEvent(wrappedJson);
        } catch (_) {}
      }
    }
    return muted;
  }

  /// Toggle camera and signal state change.
  Future<bool> toggleCamera() async {
    final enabled = _webrtcService.toggleCamera();
    if (_activeCallId != null) {
      await rust_session.setVideoEnabled(
        callId: _activeCallId!,
        enabled: enabled,
      );
      if (_remotePubkeyHex != null) {
        try {
          final wrappedJson = await rust_signaling.sendCallStateUpdate(
            callId: _activeCallId!,
            remotePubkeyHex: _remotePubkeyHex!,
            isMuted: null,
            isVideoEnabled: enabled,
          );
          await _signalingService.publishSignalingEvent(wrappedJson);
        } catch (_) {}
      }
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
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        stateStr = 'checking';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        stateStr = 'connected';
        _callStateController.add(
          CallStateEvent(callId: callId, state: 'active'),
        );
        rust_session.updateSessionState(callId: callId, state: 'active');
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        stateStr = 'disconnected';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        stateStr = 'failed';
        _callStateController.add(
          CallStateEvent(callId: callId, state: 'failed'),
        );
        rust_session.updateSessionState(callId: callId, state: 'failed');
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        stateStr = 'closed';
    }

    rust_webrtc.updatePeerState(
      callId: callId,
      participantPubkeyHex: event.remotePubkeyHex,
      state: stateStr,
    );
  }

  Future<void> _sendIceCandidate(IceCandidateEvent event) async {
    final callId = _activeCallId;
    final remotePubkey = _remotePubkeyHex;
    if (callId == null || remotePubkey == null) return;

    try {
      final wrappedJson = await rust_signaling.sendIceCandidate(
        candidate: event.candidate.candidate!,
        sdpMid: event.candidate.sdpMid,
        sdpMLineIndex: event.candidate.sdpMLineIndex,
        callId: callId,
        remotePubkeyHex: remotePubkey,
      );
      await _signalingService.publishSignalingEvent(wrappedJson);
    } catch (_) {
      // ICE candidate send failure — non-fatal, connectivity may still work
    }
  }

  /// Dispose the call manager and release all resources.
  Future<void> dispose() async {
    await stopListening();
    if (_activeCallId != null) {
      await endCall(_activeCallId!);
    }
    await _signalingService.dispose();
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
