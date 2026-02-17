import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatListTile extends StatelessWidget {
  final String name;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final int memberCount;
  final bool isDirectMessage;
  final File? avatarFile;
  final String? networkAvatarUrl;
  final bool isMuted;
  final VoidCallback? onTap;

  const ChatListTile({
    super.key,
    required this.name,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.memberCount = 0,
    this.isDirectMessage = false,
    this.avatarFile,
    this.networkAvatarUrl,
    this.isMuted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        key: avatarFile != null
            ? ValueKey(
                '${avatarFile!.path}_${avatarFile!.lastModifiedSync().millisecondsSinceEpoch}',
              )
            : networkAvatarUrl != null
            ? ValueKey(networkAvatarUrl)
            : null,
        radius: 26,
        backgroundColor: isDirectMessage
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        backgroundImage: avatarFile != null
            ? FileImage(avatarFile!)
            : networkAvatarUrl != null
            ? NetworkImage(networkAvatarUrl!)
            : null,
        child: (avatarFile != null || networkAvatarUrl != null)
            ? null
            : isDirectMessage
            ? Icon(
                Icons.person,
                color: theme.colorScheme.onTertiaryContainer,
                size: 24,
              )
            : Text(
                _initials(name),
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w500,
          fontSize: 16,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: lastMessage != null
          ? Text(
              lastMessage!,
              style: TextStyle(
                color: unreadCount > 0
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withAlpha(150),
                fontWeight: unreadCount > 0
                    ? FontWeight.w500
                    : FontWeight.normal,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              isDirectMessage
                  ? 'No messages yet'
                  : (memberCount > 0
                        ? '$memberCount members'
                        : 'No messages yet'),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withAlpha(120),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMessageTime != null)
            Text(
              _formatTimestamp(lastMessageTime!),
              style: TextStyle(
                fontSize: 12,
                color: unreadCount > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
          if (isMuted) ...[
            const SizedBox(height: 2),
            Icon(
              Icons.notifications_off,
              size: 16,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ],
          if (unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && now.day == dt.day) {
      return DateFormat.jm().format(dt);
    } else if (diff.inDays == 1 || (diff.inDays == 0 && now.day != dt.day)) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat.E().format(dt);
    } else {
      return DateFormat.MMMd().format(dt);
    }
  }
}
