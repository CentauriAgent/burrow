import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/models/meeting_notes.dart';
import 'package:burrow_app/providers/meeting_notes_provider.dart';
import 'package:burrow_app/widgets/action_item_tile.dart';

/// Post-call meeting summary screen showing notes, action items, decisions.
class MeetingSummaryScreen extends ConsumerWidget {
  final String meetingId;

  const MeetingSummaryScreen({super.key, required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesState = ref.watch(meetingNotesProvider);
    final notes = notesState.archive
        .where((n) => n.meetingId == meetingId)
        .firstOrNull;
    final theme = Theme.of(context);

    if (notes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meeting Summary')),
        body: const Center(child: Text('Meeting notes not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(notes.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export as Markdown',
            onPressed: () {
              final md = ref
                  .read(meetingNotesProvider.notifier)
                  .exportMarkdown(meetingId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exported: ${md.length} chars')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          _MetadataCard(notes: notes),
          const SizedBox(height: 16),

          // Summary
          _SectionCard(
            title: 'Summary',
            icon: Icons.summarize,
            child: Text(notes.summary, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 12),

          // Key Points
          if (notes.keyPoints.isNotEmpty) ...[
            _SectionCard(
              title: 'Key Discussion Points',
              icon: Icons.list,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: notes.keyPoints
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(p)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Action Items
          if (notes.actionItems.isNotEmpty) ...[
            _SectionCard(
              title: 'Action Items (${notes.pendingActionItems} pending)',
              icon: Icons.checklist,
              child: Column(
                children: notes.actionItems.map((item) {
                  return ActionItemTile(
                    item: item,
                    onToggle: (_) {
                      ref
                          .read(meetingNotesProvider.notifier)
                          .toggleActionItem(meetingId, item.id);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Decisions
          if (notes.decisions.isNotEmpty) ...[
            _SectionCard(
              title: 'Decisions',
              icon: Icons.gavel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: notes.decisions
                    .map(
                      (d) => ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.check_circle_outline,
                          size: 20,
                        ),
                        title: Text(d.description),
                        subtitle: d.proposedBy.isNotEmpty
                            ? Text('Proposed by ${d.proposedBy}')
                            : null,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Open Questions
          if (notes.openQuestions.isNotEmpty) ...[
            _SectionCard(
              title: 'Open Questions',
              icon: Icons.help_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: notes.openQuestions
                    .map(
                      (q) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '?  ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Expanded(child: Text(q)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final MeetingNotes notes;
  const _MetadataCard({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _MetaItem(icon: Icons.timer, label: notes.formattedDuration),
            const SizedBox(width: 24),
            _MetaItem(
              icon: Icons.people,
              label: '${notes.participants.length} participants',
            ),
            const SizedBox(width: 24),
            _MetaItem(
              icon: Icons.checklist,
              label: '${notes.actionItems.length} actions',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
