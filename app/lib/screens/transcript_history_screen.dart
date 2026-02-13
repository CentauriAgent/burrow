import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/meeting_notes_provider.dart';
import 'package:burrow_app/models/meeting_notes.dart';
import 'package:burrow_app/screens/meeting_summary_screen.dart';

/// Searchable list of past meeting transcripts and notes.
class TranscriptHistoryScreen extends ConsumerStatefulWidget {
  const TranscriptHistoryScreen({super.key});

  @override
  ConsumerState<TranscriptHistoryScreen> createState() =>
      _TranscriptHistoryScreenState();
}

class _TranscriptHistoryScreenState
    extends ConsumerState<TranscriptHistoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(meetingNotesProvider);
    final theme = Theme.of(context);

    final meetings = notesState.searchQuery.isNotEmpty
        ? notesState.searchResults
        : notesState.archive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting History'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search meetings, action items, topics...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      ref
                          .read(meetingNotesProvider.notifier)
                          .searchHistory('');
                    },
                  ),
              ],
              onChanged: (q) =>
                  ref.read(meetingNotesProvider.notifier).searchHistory(q),
            ),
          ),

          // Results count
          if (notesState.searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${meetings.length} result(s) for "${notesState.searchQuery}"',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),

          // Meeting list
          Expanded(
            child: meetings.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          notesState.archive.isEmpty
                              ? 'No meetings yet'
                              : 'No results found',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (notesState.archive.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Meeting notes will appear here after calls with transcription enabled.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: meetings.length,
                    itemBuilder: (context, index) {
                      // Show newest first.
                      final notes =
                          meetings[meetings.length - 1 - index];
                      return _MeetingListTile(
                        notes: notes,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MeetingSummaryScreen(
                              meetingId: notes.meetingId,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MeetingListTile extends StatelessWidget {
  final MeetingNotes notes;
  final VoidCallback onTap;

  const _MeetingListTile({required this.notes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(notes.startTimeMs);
    final dateStr =
        '${date.month}/${date.day}/${date.year}';

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.summarize,
          color: theme.colorScheme.onPrimaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        notes.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$dateStr • ${notes.formattedDuration} • ${notes.participants.length} participants',
      ),
      trailing: notes.pendingActionItems > 0
          ? Badge.count(
              count: notes.pendingActionItems,
              child: const Icon(Icons.checklist),
            )
          : null,
    );
  }
}
