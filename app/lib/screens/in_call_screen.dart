import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:burrow_app/providers/call_provider.dart';

/// In-call screen for active audio and video calls.
///
/// Audio-only: shows avatar + timer + controls.
/// Video: shows remote video full-screen, local PiP, auto-hiding controls.
class InCallScreen extends ConsumerStatefulWidget {
  const InCallScreen({super.key});

  @override
  ConsumerState<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends ConsumerState<InCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    setState(() => _renderersInitialized = true);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    // Assign streams to renderers
    if (_renderersInitialized) {
      if (callState.localStream != null) {
        _localRenderer.srcObject = callState.localStream;
      }
      if (callState.remoteStream != null) {
        _remoteRenderer.srcObject = callState.remoteStream;
      }
    }

    if (callState.status == CallStatus.ended ||
        callState.status == CallStatus.failed) {
      return _buildEndedScreen(callState);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => ref.read(callProvider.notifier).toggleControls(),
        child: Stack(
          children: [
            // Main content
            if (callState.isVideo)
              _buildVideoView(callState)
            else
              _buildAudioView(callState),

            // Connecting overlay
            if (callState.status == CallStatus.connecting)
              _buildConnectingOverlay(),

            // Controls overlay
            if (callState.controlsVisible ||
                callState.status != CallStatus.active)
              _buildControlsOverlay(callState),

            // Local PiP (video only)
            if (callState.isVideo &&
                _renderersInitialized &&
                callState.localStream != null)
              _buildLocalPip(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoView(CallState callState) {
    if (!_renderersInitialized || callState.remoteStream == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white24, size: 64),
        ),
      );
    }
    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildAudioView(CallState callState) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.brown.shade900, Colors.black],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.brown.shade700,
              ),
              child: callState.remoteAvatarUrl != null
                  ? ClipOval(
                      child: Image.network(callState.remoteAvatarUrl!,
                          fit: BoxFit.cover),
                    )
                  : const Icon(Icons.person, size: 56, color: Colors.white70),
            ),
            const SizedBox(height: 24),

            // Name
            Text(
              callState.remoteName ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Duration
            if (callState.callDuration != null)
              Text(
                _formatDuration(callState.callDuration!),
                style: const TextStyle(color: Colors.white54, fontSize: 18),
              ),

            // Quality indicator
            if (callState.connectionQuality != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _QualityIndicator(quality: callState.connectionQuality!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Connecting...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(CallState callState) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timer (video mode)
                if (callState.isVideo && callState.callDuration != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _formatDuration(callState.callDuration!),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),

                // Controls row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute
                    _ControlButton(
                      icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                      label: callState.isMuted ? 'Unmute' : 'Mute',
                      isActive: callState.isMuted,
                      onPressed: () =>
                          ref.read(callProvider.notifier).toggleMute(),
                    ),

                    // Camera toggle (video only)
                    if (callState.isVideo)
                      _ControlButton(
                        icon: callState.isCameraEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        label: 'Camera',
                        isActive: !callState.isCameraEnabled,
                        onPressed: () =>
                            ref.read(callProvider.notifier).toggleCamera(),
                      ),

                    // Speaker
                    _ControlButton(
                      icon: callState.isSpeakerOn
                          ? Icons.volume_up
                          : Icons.volume_down,
                      label: 'Speaker',
                      isActive: callState.isSpeakerOn,
                      onPressed: () =>
                          ref.read(callProvider.notifier).toggleSpeaker(),
                    ),

                    // Switch camera (video only)
                    if (callState.isVideo)
                      _ControlButton(
                        icon: Icons.cameraswitch,
                        label: 'Flip',
                        onPressed: () =>
                            ref.read(callProvider.notifier).switchCamera(),
                      ),

                    // End call
                    _ControlButton(
                      icon: Icons.call_end,
                      label: 'End',
                      color: Colors.red,
                      onPressed: () =>
                          ref.read(callProvider.notifier).endCall(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalPip() {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).padding.top + 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 100,
          height: 140,
          child: RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildEndedScreen(CallState callState) {
    final failed = callState.status == CallStatus.failed;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.call_end : Icons.call_end_rounded,
              color: failed ? Colors.red : Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              failed ? 'Call Failed' : 'Call Ended',
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
            if (callState.callDuration != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _formatDuration(callState.callDuration!),
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () =>
                  ref.read(callProvider.notifier).dismiss(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? color;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? (isActive ? Colors.white : Colors.white24);
    final iconColor = color != null
        ? Colors.white
        : (isActive ? Colors.black : Colors.white);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bgColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: iconColor, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _QualityIndicator extends StatelessWidget {
  final String quality;

  const _QualityIndicator({required this.quality});

  @override
  Widget build(BuildContext context) {
    final (color, bars) = switch (quality) {
      'excellent' => (Colors.green, 4),
      'good' => (Colors.lightGreen, 3),
      'fair' => (Colors.orange, 2),
      _ => (Colors.red, 1),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 4; i++)
          Container(
            width: 4,
            height: 6.0 + i * 3.0,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: i < bars ? color : Colors.white24,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          quality,
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}
