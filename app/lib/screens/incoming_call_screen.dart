import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/call_provider.dart';
import 'package:burrow_app/providers/auth_provider.dart';

/// Full-screen overlay for incoming calls with accept/reject buttons.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _slideController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
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
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOut,
            )),
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
                  isVideo ? 'Incoming Video Call' : 'Incoming Audio Call',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 32),

                // Pulsing avatar
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: _buildAvatar(callState),
                ),

                const SizedBox(height: 24),

                // Caller name
                Text(
                  callState.remoteName ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                // Ringing indicator
                _RingingDots(),

                const Spacer(flex: 3),

                // Accept / Reject buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Reject
                      _CallActionButton(
                        icon: Icons.call_end,
                        color: Colors.red,
                        label: 'Decline',
                        onPressed: () {
                          ref.read(callProvider.notifier).rejectCall();
                        },
                      ),

                      // Accept
                      _CallActionButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        color: Colors.green,
                        label: 'Accept',
                        onPressed: () async {
                          final auth = ref.read(authProvider).value;
                          if (auth == null) return;
                          await ref.read(callProvider.notifier).acceptCall(
                                localPubkeyHex: auth.account.pubkeyHex,
                              );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
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

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}

/// Animated "ringing" dots indicator.
class _RingingDots extends StatefulWidget {
  @override
  State<_RingingDots> createState() => _RingingDotsState();
}

class _RingingDotsState extends State<_RingingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final offset = i * 0.2;
            final opacity =
                (sin((_controller.value - offset) * 2 * pi) + 1) / 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: const Text(
                  '•',
                  style: TextStyle(color: Colors.white54, fontSize: 24),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
