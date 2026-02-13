import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final DateTime timestamp;
  final bool isSent;
  final String? senderName;
  final bool showSenderName;

  const ChatBubble({
    super.key,
    required this.content,
    required this.timestamp,
    required this.isSent,
    this.senderName,
    this.showSenderName = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isSent
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isSent
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final timeColor = isSent
        ? theme.colorScheme.onPrimary.withAlpha(180)
        : theme.colorScheme.onSurface.withAlpha(140);

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isSent ? 64 : 12,
          right: isSent ? 12 : 64,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isSent ? 18 : 4),
            bottomRight: Radius.circular(isSent ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSenderName && senderName != null) ...[
              Text(
                senderName!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _senderColor(senderName!),
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              content,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(timestamp),
                  style: TextStyle(fontSize: 11, color: timeColor),
                ),
                if (isSent) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all, size: 14, color: timeColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return DateFormat.jm().format(dt);
  }

  /// Deterministic color for sender name based on hash.
  Color _senderColor(String name) {
    final colors = [
      Colors.tealAccent,
      Colors.orangeAccent,
      Colors.pinkAccent,
      Colors.lightBlueAccent,
      Colors.greenAccent,
      Colors.purpleAccent,
      Colors.amberAccent,
      Colors.cyanAccent,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}
