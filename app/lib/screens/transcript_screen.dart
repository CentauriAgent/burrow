import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/transcription_provider.dart';
import 'package:burrow_app/widgets/transcript_bubble.dart';
import 'package:burrow_app/services/transcription_service.dart';

/// Live transcript view displayed during an active call.
///
/// Shows real-time transcript segments with speaker labels, timestamps,
/// and a search bar. Can be shown as a bottom sheet or side panel.
class TranscriptScreen extends ConsumerStatefulWidget {
  const TranscriptScreen({super.key});

  @override
  ConsumerState<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends ConsumerState<TranscriptScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _autoScroll = true;
  bool _isSearching = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txState = ref.watch(transcriptionProvider);
    final theme = Theme.of(context);

    final displaySegments = _isSearching && txState.searchQuery != null && txState.searchQuery!.isNotEmpty
        ? txState.searchResults
        : txState.segments;

    // Auto-scroll to bottom when new segments arrive.
    if (_autoScroll && txState.segments.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transcript...',
                  border: InputBorder.none,
                ),
                onChanged: (q) =>
                    ref.read(transcriptionProvider.notifier).search(q),
              )
            : Row(
                children: [
                  const Text('Live Transcript'),
                  const SizedBox(width: 8),
                  _StatusIndicator(status: txState.status),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref.read(transcriptionProvider.notifier).search('');
                }
              });
            },
          ),
          IconButton(
            icon: Icon(txState.isActive ? Icons.pause : Icons.play_arrow),
            tooltip: txState.isActive ? 'Pause' : 'Resume',
            onPressed: () =>
                ref.read(transcriptionProvider.notifier).togglePause(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') {
                _exportTranscript();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Export transcript'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Segment count bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Text(
                  '${displaySegments.length} segment(s)',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                if (!_autoScroll)
                  TextButton.icon(
                    onPressed: () => setState(() => _autoScroll = true),
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: const Text('Auto-scroll'),
                  ),
              ],
            ),
          ),
          // Transcript list
          Expanded(
            child: displaySegments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic_none,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          txState.isActive
                              ? 'Listening...'
                              : 'Transcription not active',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is UserScrollNotification) {
                        setState(() => _autoScroll = false);
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: displaySegments.length,
                      itemBuilder: (context, index) {
                        final seg = displaySegments[index];
                        final showSpeaker = index == 0 ||
                            displaySegments[index - 1].speakerId !=
                                seg.speakerId;
                        return TranscriptBubble(
                          segment: seg,
                          showSpeaker: showSpeaker,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _exportTranscript() {
    final text =
        ref.read(transcriptionProvider.notifier).getFormattedTranscript();
    // In production: share via platform share sheet or save to file.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Transcript: ${text.length} characters')),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final TranscriptionStatus status;
  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      TranscriptionStatus.transcribing => (Colors.red, 'LIVE'),
      TranscriptionStatus.paused => (Colors.amber, 'PAUSED'),
      TranscriptionStatus.loading => (Colors.blue, 'LOADING'),
      TranscriptionStatus.ready => (Colors.green, 'READY'),
      _ => (Colors.grey, 'OFF'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == TranscriptionStatus.transcribing)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
