import 'package:flutter/material.dart';
import 'package:burrow_app/models/meeting_notes.dart';

/// Displays an action item as a checkable list tile.
class ActionItemTile extends StatelessWidget {
  final ActionItem item;
  final ValueChanged<bool?>? onToggle;

  const ActionItemTile({
    super.key,
    required this.item,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CheckboxListTile(
      value: item.completed,
      onChanged: onToggle,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        item.description,
        style: theme.textTheme.bodyMedium?.copyWith(
          decoration:
              item.completed ? TextDecoration.lineThrough : null,
          color: item.completed
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (item.assigneeName.isNotEmpty) ...[
            Icon(Icons.person_outline,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(item.assigneeName,
                style: theme.textTheme.bodySmall),
            const SizedBox(width: 12),
          ],
          _PriorityChip(priority: item.priority),
          if (item.deadline.isNotEmpty) ...[
            const SizedBox(width: 8),
            Icon(Icons.calendar_today,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(item.deadline, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String priority;
  const _PriorityChip({required this.priority});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (priority) {
      'high' => (Colors.red, 'High'),
      'low' => (Colors.grey, 'Low'),
      _ => (Colors.orange, 'Med'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
