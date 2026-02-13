import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/call_provider.dart';

/// Full-screen overlay for outgoing calls (ringing remote peer).
class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({super.key});

  @override
  ConsumerState<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _ringController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final isVideo = callState.isVideo;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.brown.shade900.withValues(alpha: 0.8),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeController,
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Call type indicator
                Icon(
                  isVideo ? Icons.videocam : Icons.phone,
                  color: Colors.white54,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  isVideo ? 'Video Call' : 'Audio Call',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 32),

                // Pulsing ring animation around avatar
                AnimatedBuilder(
                  animation: _ringController,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Expanding rings
                        for (int i = 0; i < 3; i++)
                          _buildRing((_ringController.value + i * 0.33) % 1.0),
                        child!,
                      ],
                    );
                  },
                  child: _buildAvatar(callState),
                ),

                const SizedBox(height: 24),

                // Callee name
                Text(
                  callState.remoteName ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 12),

                // "Calling..." text
                const Text(
                  'Calling...',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),

                const Spacer(flex: 3),

                // Cancel button
                _CancelCallButton(
                  onPressed: () {
                    ref.read(callProvider.notifier).rejectCall();
                  },
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double progress) {
    final size = 120.0 + (progress * 60.0);
    final opacity = (1.0 - progress).clamp(0.0, 0.4);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.brown.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }

  Widget _buildAvatar(CallState callState) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.brown.shade700,
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: callState.remoteAvatarUrl != null
          ? ClipOval(
              child: Image.network(
                callState.remoteAvatarUrl!,
                fit: BoxFit.cover,
              ),
            )
          : const Icon(Icons.person, size: 56, color: Colors.white70),
    );
  }
}

class _CancelCallButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CancelCallButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.red,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 72,
              height: 72,
              child: Icon(Icons.call_end, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Cancel',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
