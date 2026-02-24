import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:burrow_app/services/media_attachment_service.dart';
import 'package:burrow_app/providers/messages_provider.dart';

/// Default reaction emojis shown in the quick-react bar.
const kDefaultReactions = ['❤️', '👍', '👎', '😂', '😮', '😢'];

class ChatBubble extends StatelessWidget {
  final String content;
  final DateTime timestamp;
  final bool isSent;
  final String? senderName;
  final bool showSenderName;
  final List<MediaAttachment> attachments;
  final String? groupId;
  final List<Reaction> reactions;
  final String? selfPubkey;
  final void Function(String emoji)? onReact;

  const ChatBubble({
    super.key,
    required this.content,
    required this.timestamp,
    required this.isSent,
    this.senderName,
    this.showSenderName = false,
    this.attachments = const [],
    this.groupId,
    this.reactions = const [],
    this.selfPubkey,
    this.onReact,
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

    final isMediaOnly =
        attachments.isNotEmpty && attachments.any((a) => a.filename == content);

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isSent ? 64 : 12,
          right: isSent ? 12 : 64,
          top: 2,
          bottom: reactions.isEmpty ? 2 : 0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSent && showSenderName && senderName != null)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: _senderColor(senderName!).withAlpha(80),
                  child: Text(
                    _avatarInitials(senderName!),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _senderColor(senderName!),
                    ),
                  ),
                ),
              )
            else if (!isSent && senderName != null)
              const SizedBox(width: 34), // align with avatar above
            Flexible(
              child: Column(
                crossAxisAlignment: isSent
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // The bubble itself — long press to show reaction bar
                  GestureDetector(
                    onLongPressStart: onReact != null
                        ? (details) => _showReactionBar(context, details)
                        : null,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isSent ? 18 : 4),
                          bottomRight: Radius.circular(isSent ? 4 : 18),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final attachment in attachments)
                            if (attachment.isImage)
                              _ImageAttachmentWidget(
                                attachment: attachment,
                                groupId: groupId,
                              ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
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
                                if (!isMediaOnly)
                                  MarkdownBody(
                                    data: content,
                                    selectable: true,
                                    onTapLink: (text, href, title) {
                                      if (href != null) {
                                        launchUrl(Uri.parse(href));
                                      }
                                    },
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(
                                        color: textColor,
                                        fontSize: 15,
                                        height: 1.3,
                                      ),
                                      a: TextStyle(
                                        color: textColor,
                                        decoration: TextDecoration.underline,
                                      ),
                                      code: TextStyle(
                                        color: textColor,
                                        backgroundColor: textColor.withAlpha(
                                          25,
                                        ),
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                      ),
                                      codeblockDecoration: BoxDecoration(
                                        color: textColor.withAlpha(20),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      blockquoteDecoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: textColor.withAlpha(80),
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      listBullet: TextStyle(
                                        color: textColor,
                                        fontSize: 15,
                                      ),
                                      h1: TextStyle(
                                        color: textColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      h2: TextStyle(
                                        color: textColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      h3: TextStyle(
                                        color: textColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                for (final attachment in attachments)
                                  if (attachment.isAudio)
                                    _AudioAttachmentWidget(
                                      attachment: attachment,
                                      groupId: groupId,
                                      textColor: textColor,
                                    )
                                  else if (!attachment.isImage)
                                    _FileAttachmentChip(
                                      attachment: attachment,
                                      groupId: groupId,
                                      textColor: textColor,
                                    ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTime(timestamp),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: timeColor,
                                      ),
                                    ),
                                    if (isSent) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.done_all,
                                        size: 14,
                                        color: timeColor,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Reaction pills below the bubble
                  if (reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: _ReactionPills(
                        reactions: reactions,
                        selfPubkey: selfPubkey,
                        onTap: onReact,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionBar(BuildContext context, LongPressStartDetails details) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final bubblePos = renderBox.localToGlobal(Offset.zero);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Dismiss on tap anywhere
          Positioned.fill(
            child: GestureDetector(
              onTap: () => entry.remove(),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          // Reaction bar positioned above the bubble
          Positioned(
            left: isSent ? null : bubblePos.dx,
            right: isSent
                ? MediaQuery.of(context).size.width -
                      bubblePos.dx -
                      renderBox.size.width
                : null,
            top: bubblePos.dy - 48,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(24),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final emoji in kDefaultReactions)
                      _ReactionButton(
                        emoji: emoji,
                        onTap: () {
                          entry.remove();
                          onReact?.call(emoji);
                        },
                      ),
                    // Emoji picker button
                    _ReactionButton(
                      emoji: '➕',
                      onTap: () {
                        entry.remove();
                        _showEmojiPicker(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
  }

  void _showEmojiPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SizedBox(
        height: 300,
        child: GridView.count(
          crossAxisCount: 8,
          padding: const EdgeInsets.all(16),
          children:
              [
                    '❤️',
                    '🧡',
                    '💛',
                    '💚',
                    '💙',
                    '💜',
                    '🖤',
                    '🤍',
                    '👍',
                    '👎',
                    '👏',
                    '🙌',
                    '🤝',
                    '✌️',
                    '🤞',
                    '💪',
                    '😀',
                    '😂',
                    '🤣',
                    '😍',
                    '🥰',
                    '😘',
                    '😮',
                    '😢',
                    '😡',
                    '🤔',
                    '🙄',
                    '😱',
                    '🥳',
                    '🤯',
                    '😎',
                    '🤓',
                    '🔥',
                    '⭐',
                    '💯',
                    '✅',
                    '❌',
                    '⚡',
                    '🎉',
                    '💎',
                    '🚀',
                    '🌙',
                    '☀️',
                    '🌈',
                    '🍕',
                    '🎵',
                    '📌',
                    '🏆',
                  ]
                  .map(
                    (emoji) => InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(ctx);
                        onReact?.call(emoji);
                      },
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) => DateFormat.jm().format(dt);

  String _avatarInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

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

/// Quick-react button in the reaction bar.
class _ReactionButton extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionButton({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

/// Reaction pills displayed below a bubble (grouped by emoji with count).
class _ReactionPills extends StatelessWidget {
  final List<Reaction> reactions;
  final String? selfPubkey;
  final void Function(String emoji)? onTap;

  const _ReactionPills({required this.reactions, this.selfPubkey, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Group by emoji, count occurrences
    final groups = <String, int>{};
    final selfReacted = <String>{};
    for (final r in reactions) {
      groups[r.emoji] = (groups[r.emoji] ?? 0) + 1;
      if (r.authorPubkeyHex == selfPubkey) {
        selfReacted.add(r.emoji);
      }
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: groups.entries.map((e) {
        final isMine = selfReacted.contains(e.key);
        return GestureDetector(
          onTap: () => onTap?.call(e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isMine
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: isMine
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 14)),
                if (e.value > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    '${e.value}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Downloads and displays an encrypted image attachment.
class _ImageAttachmentWidget extends StatefulWidget {
  final MediaAttachment attachment;
  final String? groupId;

  const _ImageAttachmentWidget({required this.attachment, this.groupId});

  @override
  State<_ImageAttachmentWidget> createState() => _ImageAttachmentWidgetState();
}

class _ImageAttachmentWidgetState extends State<_ImageAttachmentWidget> {
  File? _file;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    if (widget.groupId == null) {
      setState(() {
        _loading = false;
        _error = 'No group context';
      });
      return;
    }
    try {
      final file = await MediaAttachmentService.downloadAttachment(
        groupId: widget.groupId!,
        attachment: widget.attachment,
      );
      if (mounted)
        setState(() {
          _file = file;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Failed to load';
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null || _file == null) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, size: 32, color: Colors.grey),
              const SizedBox(height: 4),
              Text(
                _error ?? 'Image unavailable',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return Image.file(
      _file!,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, __, ___) => const SizedBox(
        height: 100,
        child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      ),
    );
  }
}

/// Downloads, decrypts, and plays an audio attachment with playback controls.
class _AudioAttachmentWidget extends StatefulWidget {
  final MediaAttachment attachment;
  final String? groupId;
  final Color textColor;

  const _AudioAttachmentWidget({
    required this.attachment,
    this.groupId,
    required this.textColor,
  });

  @override
  State<_AudioAttachmentWidget> createState() => _AudioAttachmentWidgetState();
}

class _AudioAttachmentWidgetState extends State<_AudioAttachmentWidget> {
  final AudioPlayer _player = AudioPlayer();
  File? _file;
  bool _loading = true;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _download();
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      }
    });
  }

  Future<void> _download() async {
    if (widget.groupId == null) {
      setState(() {
        _loading = false;
        _error = 'No group context';
      });
      return;
    }
    try {
      final file =
          await MediaAttachmentService.downloadAttachment(
            groupId: widget.groupId!,
            attachment: widget.attachment,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Download timed out'),
          );
      if (!file.existsSync() || file.lengthSync() == 0) {
        throw Exception('Downloaded file is empty or missing');
      }
      try {
        await _player.setFilePath(file.path);
      } catch (playerError) {
        // Fallback: try setting as a file URI (some platforms need this)
        await _player.setUrl('file://${file.path}');
      }
      if (mounted) {
        setState(() {
          _file = file;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().length > 60
              ? 'Failed to load audio'
              : 'Audio: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading audio...',
              style: TextStyle(color: widget.textColor, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_error != null || _file == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 18,
              color: widget.textColor.withAlpha(180),
            ),
            const SizedBox(width: 6),
            Text(
              _error ?? 'Audio unavailable',
              style: TextStyle(color: widget.textColor, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _isPlaying ? _player.pause() : _player.play(),
            child: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 32,
              color: widget.textColor,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 16,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: widget.textColor,
                      inactiveTrackColor: widget.textColor.withAlpha(60),
                      thumbColor: widget.textColor,
                    ),
                    child: Slider(
                      min: 0,
                      max: _duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      value: _position.inMilliseconds.toDouble().clamp(
                        0,
                        _duration.inMilliseconds.toDouble().clamp(
                          1,
                          double.infinity,
                        ),
                      ),
                      onChanged: (v) =>
                          _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                ),
                Text(
                  '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.textColor.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a non-image attachment as a tappable file chip.
class _FileAttachmentChip extends StatelessWidget {
  final MediaAttachment attachment;
  final String? groupId;
  final Color textColor;

  const _FileAttachmentChip({
    required this.attachment,
    this.groupId,
    required this.textColor,
  });

  IconData get _icon {
    if (attachment.isVideo) return Icons.videocam;
    if (attachment.isAudio) return Icons.audiotrack;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 18, color: textColor.withAlpha(180)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.filename,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                decoration: TextDecoration.underline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
