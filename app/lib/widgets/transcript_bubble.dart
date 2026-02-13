import 'package:flutter/material.dart';
import 'package:burrow_app/models/transcript.dart';

/// Displays a single transcript segment with speaker label and timestamp.
class TranscriptBubble extends StatelessWidget {
  final TranscriptSegment segment;
  final bool showSpeaker;
  final VoidCallback? onTap;

  const TranscriptBubble({
    super.key,
    required this.segment,
    this.showSpeaker = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInterim = !segment.isFinal;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            SizedBox(
              width: 52,
              child: Text(
                segment.formattedTime,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSpeaker)
                    Text(
                      segment.speakerName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _speakerColor(segment.speakerId, theme),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    segment.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle:
                          isInterim ? FontStyle.italic : FontStyle.normal,
                      color: isInterim
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            // Confidence indicator
            if (segment.confidence > 0 && segment.confidence < 0.7)
              Tooltip(
                message:
                    'Low confidence: ${(segment.confidence * 100).toInt()}%',
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: theme.colorScheme.error.withAlpha(153),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Assign consistent colors to speakers based on their ID hash.
  Color _speakerColor(String speakerId, ThemeData theme) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
    ];
    final hash = speakerId.hashCode.abs();
    return colors[hash % colors.length];
  }
}
