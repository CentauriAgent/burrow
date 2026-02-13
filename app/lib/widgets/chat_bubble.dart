import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:burrow_app/services/media_attachment_service.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final DateTime timestamp;
  final bool isSent;
  final String? senderName;
  final bool showSenderName;
  final List<MediaAttachment> attachments;
  final String? groupId;

  const ChatBubble({
    super.key,
    required this.content,
    required this.timestamp,
    required this.isSent,
    this.senderName,
    this.showSenderName = false,
    this.attachments = const [],
    this.groupId,
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

    // Check if content is just a filename matching an attachment
    final isMediaOnly =
        attachments.isNotEmpty && attachments.any((a) => a.filename == content);

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
            // Media attachments
            for (final attachment in attachments)
              if (attachment.isImage)
                _ImageAttachmentWidget(
                  attachment: attachment,
                  groupId: groupId,
                ),

            // Text content area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  // Show text content unless it's just the filename
                  if (!isMediaOnly)
                    Text(
                      content,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  // Non-image attachments shown as file chips
                  for (final attachment in attachments)
                    if (!attachment.isImage)
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
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return DateFormat.jm().format(dt);
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
