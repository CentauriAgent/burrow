/// WebRTC media service wrapping flutter_webrtc plugin.
///
/// Handles local media streams, peer connection lifecycle, and media controls.
/// All signaling and crypto is delegated to the Rust core via FFI bridge.
library;

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:burrow_app/src/rust/api/call_webrtc.dart' as rust_webrtc;
import 'package:burrow_app/services/turn_settings.dart';

/// Manages WebRTC peer connections and local media for calls.
class WebRtcService {
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  // Stream controllers for events
  final _remoteStreamController =
      StreamController<RemoteStreamEvent>.broadcast();
  final _connectionStateController =
      StreamController<PeerConnectionStateEvent>.broadcast();
  final _iceCandidateController =
      StreamController<IceCandidateEvent>.broadcast();

  /// Emits when a remote stream is added or removed.
  Stream<RemoteStreamEvent> get onRemoteStream =>
      _remoteStreamController.stream;

  /// Emits when a peer connection state changes.
  Stream<PeerConnectionStateEvent> get onConnectionState =>
      _connectionStateController.stream;

  /// Emits when a local ICE candidate is generated (must be sent to remote via signaling).
  Stream<IceCandidateEvent> get onIceCandidate =>
      _iceCandidateController.stream;

  /// The local media stream (camera + mic).
  MediaStream? get localStream => _localStream;

  /// Whether local audio is currently muted.
  bool get isMuted => _isMuted;
  bool _isMuted = false;

  /// Whether local camera is enabled.
  bool get isCameraEnabled => _isCameraEnabled;
  bool _isCameraEnabled = true;

  /// Initialize local media stream (camera + microphone).
  ///
  /// [isVideo] - if true, enables camera; otherwise audio-only.
  Future<MediaStream> initializeWebRTC({bool isVideo = true}) async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': isVideo
          ? {'facingMode': 'user', 'width': 1280, 'height': 720}
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _isCameraEnabled = isVideo;
    _isMuted = false;
    return _localStream!;
  }

  /// Create a new RTCPeerConnection using ICE config from Rust core.
  ///
  /// [callId] - call identifier for ICE credential derivation.
  /// [remotePubkeyHex] - hex pubkey of remote peer (used as connection key).
  Future<RTCPeerConnection> createBurrowPeerConnection({
    required String callId,
    required String remotePubkeyHex,
  }) async {
    // Get ICE configuration from Rust
    final config = await rust_webrtc.generateWebrtcConfig(callId: callId);

    // Build ICE servers list, checking for user-configured TURN override
    var iceServers = config.iceServers
        .map(
          (s) => <String, dynamic>{
            'urls': s.urls,
            if (s.username != null) 'username': s.username,
            if (s.credential != null) 'credential': s.credential,
          },
        )
        .toList();

    // Override TURN servers with user settings if configured
    final customTurn = await TurnSettings.load();
    if (customTurn != null) {
      // Keep STUN servers (no username), replace TURN servers
      iceServers = [
        ...iceServers.where((s) => s['username'] == null),
        <String, dynamic>{
          'urls': customTurn.urls,
          if (customTurn.username != null) 'username': customTurn.username,
          if (customTurn.credential != null)
            'credential': customTurn.credential,
        },
      ];
    }

    final rtcConfig = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': config.sdpSemantics,
      'bundlePolicy': config.bundlePolicy,
    };

    final pc = await createPeerConnection(rtcConfig);

    // Add local tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    // Handle ICE candidates
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_iceCandidateController.isClosed) {
        _iceCandidateController.add(
          IceCandidateEvent(
            remotePubkeyHex: remotePubkeyHex,
            candidate: candidate,
          ),
        );
      }
    };

    // Handle remote tracks
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && !_remoteStreamController.isClosed) {
        _remoteStreamController.add(
          RemoteStreamEvent(
            remotePubkeyHex: remotePubkeyHex,
            stream: event.streams[0],
            isAdded: true,
          ),
        );
      }
    };

    // Handle connection state changes
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (_connectionStateController.isClosed) return;
      _connectionStateController.add(
        PeerConnectionStateEvent(
          remotePubkeyHex: remotePubkeyHex,
          state: state,
        ),
      );
    };

    pc.onRemoveStream = (MediaStream stream) {
      _remoteStreamController.add(
        RemoteStreamEvent(
          remotePubkeyHex: remotePubkeyHex,
          stream: stream,
          isAdded: false,
        ),
      );
    };

    _peerConnections[remotePubkeyHex] = pc;
    return pc;
  }

  /// Create an SDP offer for the specified peer connection.
  Future<RTCSessionDescription> createOffer(String remotePubkeyHex) async {
    final pc = _peerConnections[remotePubkeyHex];
    if (pc == null) throw StateError('No peer connection for $remotePubkeyHex');

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return offer;
  }

  /// Create an SDP answer for the specified peer connection.
  ///
  /// [remoteOffer] must be set as the remote description first.
  Future<RTCSessionDescription> createAnswer(
    String remotePubkeyHex,
    RTCSessionDescription remoteOffer,
  ) async {
    final pc = _peerConnections[remotePubkeyHex];
    if (pc == null) throw StateError('No peer connection for $remotePubkeyHex');

    await pc.setRemoteDescription(remoteOffer);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer;
  }

  /// Set the remote SDP description (offer or answer) on a peer connection.
  Future<void> setRemoteDescription(
    String remotePubkeyHex,
    RTCSessionDescription description,
  ) async {
    final pc = _peerConnections[remotePubkeyHex];
    if (pc == null) throw StateError('No peer connection for $remotePubkeyHex');
    await pc.setRemoteDescription(description);
  }

  /// Add a remote ICE candidate to the specified peer connection.
  Future<void> addIceCandidate(
    String remotePubkeyHex,
    RTCIceCandidate candidate,
  ) async {
    final pc = _peerConnections[remotePubkeyHex];
    if (pc == null) throw StateError('No peer connection for $remotePubkeyHex');
    await pc.addCandidate(candidate);
  }

  /// Toggle local audio mute state.
  bool toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    return _isMuted;
  }

  /// Toggle local camera on/off.
  bool toggleCamera() {
    _isCameraEnabled = !_isCameraEnabled;
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = _isCameraEnabled;
    });
    return _isCameraEnabled;
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks[0]);
    }
  }

  /// Close a specific peer connection.
  Future<void> closePeerConnection(String remotePubkeyHex) async {
    final pc = _peerConnections.remove(remotePubkeyHex);
    await pc?.close();
    final renderer = _remoteRenderers.remove(remotePubkeyHex);
    renderer?.dispose();
  }

  /// Dispose all resources: close all peer connections and release local media.
  Future<void> dispose() async {
    // Close all peer connections
    for (final pc in _peerConnections.values) {
      try {
        await pc.close();
      } catch (_) {
        // Peer connection may already be null/closed
      }
    }
    _peerConnections.clear();

    // Dispose renderers
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();

    // Stop local stream
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    // Close stream controllers
    await _remoteStreamController.close();
    await _connectionStateController.close();
    await _iceCandidateController.close();
  }
}

// ── Event types ──────────────────────────────────────────────────────────

class RemoteStreamEvent {
  final String remotePubkeyHex;
  final MediaStream stream;
  final bool isAdded;

  RemoteStreamEvent({
    required this.remotePubkeyHex,
    required this.stream,
    required this.isAdded,
  });
}

class PeerConnectionStateEvent {
  final String remotePubkeyHex;
  final RTCPeerConnectionState state;

  PeerConnectionStateEvent({
    required this.remotePubkeyHex,
    required this.state,
  });
}

class IceCandidateEvent {
  final String remotePubkeyHex;
  final RTCIceCandidate candidate;

  IceCandidateEvent({required this.remotePubkeyHex, required this.candidate});
}
