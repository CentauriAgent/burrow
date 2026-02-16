import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:burrow_app/providers/archive_provider.dart';
import 'package:burrow_app/providers/messages_provider.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/profile_provider.dart';
import 'package:burrow_app/providers/call_provider.dart';
import 'package:burrow_app/providers/group_avatar_provider.dart';
import 'package:burrow_app/screens/chat_shell_screen.dart';
import 'package:burrow_app/widgets/chat_bubble.dart';
import 'package:burrow_app/services/media_attachment_service.dart';
import 'package:burrow_app/src/rust/api/error.dart';

class ChatViewScreen extends ConsumerStatefulWidget {
  final String groupId;

  const ChatViewScreen({super.key, required this.groupId});

  @override
  ConsumerState<ChatViewScreen> createState() => _ChatViewScreenState();
}

class _ChatViewScreenState extends ConsumerState<ChatViewScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Set the active group
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TODO: Track active group ID when state management is finalized
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messagesNotifier = ref.watch(messagesProvider(widget.groupId));
    final messages = messagesNotifier.messages;
    final groups = ref.watch(groupsProvider).value ?? [];
    final group = groups
        .where((g) => g.mlsGroupIdHex == widget.groupId)
        .firstOrNull;
    final isDm =
        (group?.isDirectMessage ?? false) && (group?.memberCount ?? 0) <= 2;
    final auth = ref.watch(authProvider);
    final selfPubkey = auth.value?.account.pubkeyHex ?? 'self';

    final isWide = MediaQuery.of(context).size.width >= 700;
    final avatar = ref.watch(groupAvatarProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        leading: isWide
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/home'),
              ),
        automaticallyImplyLeading: false,
        title: InkWell(
          onTap: () {
            if (isWide) {
              ref
                  .read(detailPaneProvider.notifier)
                  .showGroupInfo(widget.groupId);
            } else {
              context.push('/group-info/${widget.groupId}');
            }
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isDm
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.primaryContainer,
                backgroundImage: avatar.avatarFile != null
                    ? FileImage(avatar.avatarFile!)
                    : isDm && group?.dmPeerPicture != null
                    ? NetworkImage(group!.dmPeerPicture!)
                    : null,
                child:
                    (avatar.avatarFile != null ||
                        (isDm && group?.dmPeerPicture != null))
                    ? null
                    : isDm
                    ? Icon(
                        Icons.person,
                        size: 18,
                        color: theme.colorScheme.onTertiaryContainer,
                      )
                    : Text(
                        _initials(group?.displayName ?? 'Chat'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group?.displayName ?? 'Chat',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isDm && group != null && group.memberCount > 0)
                      Text(
                        '${group.memberCount} members',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                    if (isDm)
                      Text(
                        'Encrypted direct message',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Audio Call',
            onPressed: () => _startCall(context, isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call',
            onPressed: () => _startCall(context, isVideo: true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _onMenuAction(context, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'group_settings',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.settings_outlined, size: 20),
                  title: Text('Group settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'search',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.search, size: 20),
                  title: Text('Search'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'mute',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.notifications_off_outlined, size: 20),
                  title: Text('Mute notifications'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.archive_outlined, size: 20),
                  title: Text('Archive'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'leave',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.exit_to_app, size: 20, color: Colors.red),
                  title: Text(
                    'Leave group',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyChat(theme)
                : Builder(
                    builder: (context) {
                      final isGroup = (group?.memberCount ?? 0) > 2;
                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isSent =
                              msg.authorPubkeyHex == selfPubkey ||
                              msg.authorPubkeyHex == 'self';
                          final showName = isGroup && !isSent;
                          final prevMsg = index < messages.length - 1
                              ? messages[index + 1]
                              : null;
                          final showNameForThis =
                              showName &&
                              (prevMsg == null ||
                                  prevMsg.authorPubkeyHex !=
                                      msg.authorPubkeyHex);
                          final profileAsync = showName
                              ? ref.watch(
                                  memberProfileProvider(msg.authorPubkeyHex),
                                )
                              : null;
                          final resolvedName = profileAsync?.whenOrNull(
                            data: (profile) =>
                                profile?.displayName ?? profile?.name,
                          );
                          final senderName =
                              resolvedName ??
                              _shortenPubkey(msg.authorPubkeyHex);
                          final attachments =
                              MediaAttachmentService.parseAttachments(msg.tags);
                          final msgReactions = messagesNotifier.reactionsFor(
                            msg.eventIdHex,
                          );
                          return ChatBubble(
                            content: msg.content,
                            timestamp: DateTime.fromMillisecondsSinceEpoch(
                              msg.createdAt.toInt() * 1000,
                            ),
                            isSent: isSent,
                            senderName: senderName,
                            showSenderName: showNameForThis,
                            attachments: attachments,
                            groupId: widget.groupId,
                            reactions: msgReactions,
                            selfPubkey: selfPubkey,
                            onReact: (emoji) {
                              ref
                                  .read(
                                    messagesProvider(widget.groupId).notifier,
                                  )
                                  .sendReaction(msg.eventIdHex, emoji);
                            },
                          );
                        },
                      );
                    },
                  ),
          ),

          // E2E encryption notice
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 12,
                  color: theme.colorScheme.onSurface.withAlpha(80),
                ),
                const SizedBox(width: 4),
                Text(
                  'End-to-end encrypted • Marmot Protocol',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withAlpha(80),
                  ),
                ),
              ],
            ),
          ),

          // Input bar
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildEmptyChat(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: theme.colorScheme.primary.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              'End-to-end encrypted',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Messages in this chat are secured with\nthe Marmot Protocol (MLS + Nostr).',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withAlpha(130),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 8
            : MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment / plus button
          PopupMenuButton<String>(
            icon: Icon(
              Icons.add_circle_outline,
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
            offset: const Offset(0, -280),
            onSelected: _onAttachmentAction,
            itemBuilder: (context) => [
              _attachmentMenuItem(
                icon: Icons.image_outlined,
                label: 'Photo',
                value: 'photo',
                theme: theme,
              ),
              _attachmentMenuItem(
                icon: Icons.videocam_outlined,
                label: 'Video',
                value: 'video',
                theme: theme,
              ),
              _attachmentMenuItem(
                icon: Icons.insert_drive_file_outlined,
                label: 'File',
                value: 'file',
                theme: theme,
              ),
              _attachmentMenuItem(
                icon: Icons.gif_box_outlined,
                label: 'GIF',
                value: 'gif',
                theme: theme,
              ),
              const PopupMenuDivider(),
              _attachmentMenuItem(
                icon: Icons.emoji_emotions_outlined,
                label: 'Stickers',
                value: 'stickers',
                theme: theme,
              ),
            ],
          ),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _sendMessage();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),

          const SizedBox(width: 4),

          // Send button (when text) or Voice message button (when empty)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: _messageController.text.trim().isNotEmpty
                ? IconButton(
                    key: const ValueKey('send'),
                    icon: _isSending
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(Icons.send, color: theme.colorScheme.primary),
                    onPressed: _isSending ? null : _sendMessage,
                  )
                : IconButton(
                    key: const ValueKey('voice'),
                    icon: Icon(
                      Icons.mic,
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                    onPressed: _onVoiceMessage,
                    tooltip: 'Voice message',
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await ref
          .read(messagesProvider(widget.groupId).notifier)
          .sendMessage(content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }

    _focusNode.requestFocus();
  }

  PopupMenuItem<String> _attachmentMenuItem({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _onAttachmentAction(String action) async {
    switch (action) {
      case 'photo':
        await _sendPhoto();
      case 'video':
        await _sendVideo();
      case 'file':
        await _sendFile();
      default:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$action coming soon')));
    }
  }

  Future<void> _sendPhoto() async {
    final picked = await MediaAttachmentService.pickPhoto();
    if (picked == null) return;
    await _uploadAndSend(picked);
  }

  Future<void> _sendVideo() async {
    final picked = await MediaAttachmentService.pickVideo();
    if (picked == null) return;
    await _uploadAndSend(picked);
  }

  Future<void> _sendFile() async {
    final picked = await MediaAttachmentService.pickFile();
    if (picked == null || picked.path == null) return;
    final bytes = await XFile(picked.path!).readAsBytes();
    final mimeType = MediaAttachmentService.guessMimeType(picked.name);

    setState(() => _isSending = true);
    try {
      final result = await MediaAttachmentService.sendMediaMessage(
        groupId: widget.groupId,
        fileData: bytes,
        mimeType: mimeType,
        filename: picked.name,
      );
      ref
          .read(messagesProvider(widget.groupId).notifier)
          .addIncomingMessage(result.message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: ${_mediaError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _uploadAndSend(XFile file) async {
    final bytes = await file.readAsBytes();
    final mimeType =
        file.mimeType ?? MediaAttachmentService.guessMimeType(file.path);
    final filename = file.name;

    setState(() => _isSending = true);
    try {
      final result = await MediaAttachmentService.sendMediaMessage(
        groupId: widget.groupId,
        fileData: bytes,
        mimeType: mimeType,
        filename: filename,
      );
      ref
          .read(messagesProvider(widget.groupId).notifier)
          .addIncomingMessage(result.message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: ${_mediaError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _mediaError(Object e) => e is BurrowError ? e.message : e.toString();

  void _onVoiceMessage() {
    // TODO: Record audio, encrypt, upload to Blossom, send URL in message
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Voice messages coming soon')));
  }

  void _onMenuAction(BuildContext context, String action) {
    final groupId = widget.groupId;
    final isWide = MediaQuery.of(context).size.width >= 700;
    switch (action) {
      case 'group_settings':
        if (isWide) {
          ref.read(detailPaneProvider.notifier).showGroupInfo(groupId);
        } else {
          context.push('/group-info/$groupId');
        }
      case 'search':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Search coming soon')));
      case 'mute':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mute coming soon')));
      case 'archive':
        ref.read(archiveProvider.notifier).archive(groupId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Chat archived'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () =>
                  ref.read(archiveProvider.notifier).unarchive(groupId),
            ),
          ),
        );
        context.go('/home');
      case 'leave':
        _confirmLeaveGroup(context, groupId);
    }
  }

  Future<void> _confirmLeaveGroup(BuildContext context, String groupId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text(
          'Are you sure? You\'ll need a new invitation to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref.read(groupProvider.notifier).leaveFromGroup(groupId);
        if (context.mounted) context.go('/home');
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _startCall(BuildContext context, {required bool isVideo}) {
    final auth = ref.read(authProvider).value;
    if (auth == null) return;

    final group = ref
        .read(groupsProvider)
        .value
        ?.firstWhere(
          (g) => g.mlsGroupIdHex == widget.groupId,
          orElse: () => throw StateError('Group not found'),
        );

    // For 1:1 calls, use the DM peer pubkey
    String? remotePubkey = group?.dmPeerPubkeyHex;

    if (remotePubkey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calls are currently supported for 1:1 chats only'),
        ),
      );
      return;
    }

    final callId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    ref
        .read(callProvider.notifier)
        .startCall(
          remotePubkeyHex: remotePubkey,
          localPubkeyHex: auth.account.pubkeyHex,
          callId: callId,
          isVideo: isVideo,
          remoteName: group?.displayName,
        );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _shortenPubkey(String hex) {
    if (hex.length > 12) return '${hex.substring(0, 8)}...';
    return hex;
  }
}
