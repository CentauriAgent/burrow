import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/messages_provider.dart';
import 'package:burrow_app/providers/profile_provider.dart';

/// Animated typing indicator that shows "X is typing..." with bouncing dots.
///
/// Place this in the chat view between the message list and the input bar.
/// It automatically resolves pubkeys to display names and handles
/// singular/plural formatting.
class TypingIndicator extends ConsumerStatefulWidget {
  /// MLS group ID to watch for typing events.
  final String groupId;

  const TypingIndicator({super.key, required this.groupId});

  @override
  ConsumerState<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends ConsumerState<TypingIndicator>
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
    final notifier = ref.watch(messagesProvider(widget.groupId));
    final typing = notifier.typingPubkeys;

    if (typing.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final names = typing.map((pk) {
      final profile = ref.watch(memberProfileProvider(pk));
      return profile.value?.displayName ??
          profile.value?.name ??
          '${pk.substring(0, 8)}...';
    }).toList();

    final label = names.length == 1
        ? '${names[0]} is typing'
        : '${names.join(', ')} are typing';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(width: 2),
          _AnimatedDots(controller: _controller, theme: theme),
        ],
      ),
    );
  }
}

/// Three dots that bounce sequentially to indicate ongoing typing.
class _AnimatedDots extends StatelessWidget {
  final AnimationController controller;
  final ThemeData theme;

  const _AnimatedDots({required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each dot by 0.2 of the animation cycle
            final delay = i * 0.2;
            final t = (controller.value - delay) % 1.0;
            // Bounce: use a sine curve over the first half of the cycle
            final bounce = t < 0.5 ? _bounce(t * 2) : 0.0;
            return Transform.translate(
              offset: Offset(0, -3 * bounce),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  '.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// Simple ease-out bounce curve.
  double _bounce(double t) {
    return -4 * t * (t - 1); // Parabola peaking at t=0.5
  }
}
