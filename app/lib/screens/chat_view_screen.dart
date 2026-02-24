import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:burrow_app/providers/archive_provider.dart';
import 'package:burrow_app/providers/mute_provider.dart';
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
import 'package:burrow_app/src/rust/api/app_state.dart' as rust_app;
import 'package:burrow_app/src/rust/api/error.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/message.dart' as rust_message;

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

  // Search state
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<int> _searchMatchIndices = [];
  int _currentMatchIndex = -1;
  // GlobalKeys for message items, keyed by list index, used for accurate
  // scroll-to-match with variable-height message bubbles.
  final Map<int, GlobalKey> _messageKeys = {};
  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // @mention autocomplete state
  bool _showMentions = false;
  String _mentionQuery = '';
  List<rust_group.MemberInfo> _mentionCandidates = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeGroupProvider.notifier).state = widget.groupId;
      _markAsRead();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _markAsRead() {
    final messages = ref.read(messagesProvider(widget.groupId)).messages;
    if (messages.isNotEmpty) {
      final newest = messages.first;
      ref.read(groupsProvider.notifier).markGroupRead(widget.groupId);
      rust_app.markGroupRead(
        groupIdHex: widget.groupId,
        lastEventIdHex: newest.eventIdHex,
        timestamp: newest.createdAt.toInt(),
      );
    }
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
              PopupMenuItem(
                value: 'mute',
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    (ref.read(muteProvider).value ?? {}).contains(
                          widget.groupId,
                        )
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    size: 20,
                  ),
                  title: Text(
                    (ref.read(muteProvider).value ?? {}).contains(
                          widget.groupId,
                        )
                        ? 'Unmute notifications'
                        : 'Mute notifications',
                  ),
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
          // Search bar
          if (_isSearching) _buildSearchBar(theme, messages),

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
                          final isSearchMatch =
                              _isSearching &&
                              _searchQuery.isNotEmpty &&
                              msg.content.toLowerCase().contains(
                                _searchQuery.toLowerCase(),
                              );
                          final isCurrentMatch =
                              isSearchMatch &&
                              _currentMatchIndex >= 0 &&
                              _currentMatchIndex < _searchMatchIndices.length &&
                              _searchMatchIndices[_currentMatchIndex] == index;
                          // Assign a GlobalKey so search can scroll
                          // accurately to variable-height items.
                          _messageKeys.putIfAbsent(index, () => GlobalKey());
                          return Container(
                            key: _messageKeys[index],
                            color: isCurrentMatch
                                ? theme.colorScheme.tertiaryContainer.withAlpha(
                                    120,
                                  )
                                : isSearchMatch
                                ? theme.colorScheme.tertiaryContainer.withAlpha(
                                    50,
                                  )
                                : null,
                            child: msg.kind == BigInt.from(1068)
                                ? _buildPollBubble(
                                    theme,
                                    msg,
                                    isSent,
                                    senderName,
                                    showNameForThis,
                                    messagesNotifier,
                                  )
                                : ChatBubble(
                                    content: msg.content,
                                    timestamp:
                                        DateTime.fromMillisecondsSinceEpoch(
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
                                            messagesProvider(
                                              widget.groupId,
                                            ).notifier,
                                          )
                                          .sendReaction(msg.eventIdHex, emoji);
                                    },
                                  ),
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

          // @mention suggestions
          _buildMentionSuggestions(theme),

          // Typing indicator
          _buildTypingIndicator(theme, messagesNotifier),

          // Input bar
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
    ThemeData theme,
    List<rust_message.GroupMessage> messages,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search in chat...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
                suffixText: _searchMatchIndices.isNotEmpty
                    ? '${_currentMatchIndex + 1}/${_searchMatchIndices.length}'
                    : null,
                suffixStyle: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withAlpha(120),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _updateSearchMatches(messages);
                });
              },
            ),
          ),
          if (_searchMatchIndices.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: _currentMatchIndex < _searchMatchIndices.length - 1
                  ? () => _navigateSearchMatch(1, messages)
                  : null,
              tooltip: 'Previous match',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: _currentMatchIndex > 0
                  ? () => _navigateSearchMatch(-1, messages)
                  : null,
              tooltip: 'Next match',
              visualDensity: VisualDensity.compact,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _isSearching = false;
                _searchQuery = '';
                _searchMatchIndices = [];
                _currentMatchIndex = -1;
                _messageKeys.clear();
                _searchController.clear();
              });
            },
            tooltip: 'Close search',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  void _updateSearchMatches(List<rust_message.GroupMessage> messages) {
    if (_searchQuery.isEmpty) {
      _searchMatchIndices = [];
      _currentMatchIndex = -1;
      return;
    }
    final query = _searchQuery.toLowerCase();
    _searchMatchIndices = <int>[];
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].content.toLowerCase().contains(query)) {
        _searchMatchIndices.add(i);
      }
    }
    if (_searchMatchIndices.isNotEmpty) {
      _currentMatchIndex = 0;
      _scrollToMatch(messages);
    } else {
      _currentMatchIndex = -1;
    }
  }

  void _navigateSearchMatch(
    int delta,
    List<rust_message.GroupMessage> messages,
  ) {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + delta).clamp(
        0,
        _searchMatchIndices.length - 1,
      );
    });
    _scrollToMatch(messages);
  }

  void _scrollToMatch(List<rust_message.GroupMessage> messages) {
    if (_currentMatchIndex < 0 ||
        _currentMatchIndex >= _searchMatchIndices.length)
      return;
    final targetIndex = _searchMatchIndices[_currentMatchIndex];
    // Use Scrollable.ensureVisible with the message's GlobalKey for accurate
    // positioning regardless of variable-height message bubbles.
    final key = _messageKeys[targetIndex];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5, // center the match in the viewport
      );
    }
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

  void _checkForMention(String text) {
    final cursor = _messageController.selection.baseOffset;
    if (cursor <= 0) {
      setState(() => _showMentions = false);
      return;
    }

    // Find the last '@' before the cursor
    final beforeCursor = text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex < 0 ||
        (atIndex > 0 &&
            beforeCursor[atIndex - 1] != ' ' &&
            beforeCursor[atIndex - 1] != '\n')) {
      setState(() => _showMentions = false);
      return;
    }

    final query = beforeCursor.substring(atIndex + 1).toLowerCase();
    // Don't show if there's a space in the query (mention is complete)
    if (query.contains(' ')) {
      setState(() => _showMentions = false);
      return;
    }

    setState(() {
      _showMentions = true;
      _mentionQuery = query;
    });
    _loadMentionCandidates();
  }

  Future<void> _loadMentionCandidates() async {
    final query = _mentionQuery;
    try {
      final members = await rust_group.getGroupMembers(
        mlsGroupIdHex: widget.groupId,
      );
      final selfPubkey = ref.read(authProvider).value?.account.pubkeyHex;
      setState(() {
        _mentionCandidates = members
            .where((m) => m.pubkeyHex != selfPubkey)
            .where((m) {
              if (query.isEmpty) return true;
              final name = (m.displayName ?? m.pubkeyHex).toLowerCase();
              return name.contains(query);
            })
            .toList();
      });
    } catch (_) {}
  }

  void _insertMention(rust_group.MemberInfo member) {
    final text = _messageController.text;
    final cursor = _messageController.selection.baseOffset;
    final beforeCursor = text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex < 0) return;

    final name = member.displayName ?? member.pubkeyHex.substring(0, 12);
    final replacement = '@$name ';
    final newText =
        text.substring(0, atIndex) + replacement + text.substring(cursor);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIndex + replacement.length),
    );
    setState(() => _showMentions = false);
  }

  Widget _buildPollBubble(
    ThemeData theme,
    rust_message.GroupMessage msg,
    bool isSent,
    String senderName,
    bool showSenderName,
    MessagesNotifier notifier,
  ) {
    final bubbleColor = isSent
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isSent
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final selfPubkey = ref.read(authProvider).value?.account.pubkeyHex ?? '';

    // Parse poll options from tags
    final options = <String>[];
    for (final tag in msg.tags) {
      if (tag.length >= 3 && tag[0] == 'poll_option') {
        options.add(tag[2]);
      }
    }

    final votes = notifier.votesFor(msg.eventIdHex);
    final myVote = votes
        .where((v) => v.voterPubkeyHex == selfPubkey)
        .firstOrNull;
    final totalVotes = votes.length;

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isSent ? 64 : 12,
          right: isSent ? 12 : 64,
          top: 2,
          bottom: 2,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSenderName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    senderName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor.withAlpha(180),
                    ),
                  ),
                ),
              Row(
                children: [
                  Icon(Icons.poll, size: 18, color: textColor.withAlpha(180)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Poll',
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withAlpha(150),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg.content,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              ...options.asMap().entries.map((entry) {
                final i = entry.key;
                final option = entry.value;
                final optionVotes = votes
                    .where((v) => v.optionIndex == i)
                    .length;
                final pct = totalVotes > 0 ? optionVotes / totalVotes : 0.0;
                final isMyVote = myVote?.optionIndex == i;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: myVote == null
                        ? () => ref
                              .read(messagesProvider(widget.groupId).notifier)
                              .sendPollVote(msg.eventIdHex, i)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isMyVote ? textColor : textColor.withAlpha(60),
                          width: isMyVote ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: TextStyle(color: textColor, fontSize: 14),
                            ),
                          ),
                          if (myVote != null)
                            Text(
                              '${(pct * 100).round()}%',
                              style: TextStyle(
                                color: textColor.withAlpha(150),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (totalVotes > 0)
                Text(
                  '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: textColor.withAlpha(120),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePollDialog() {
    final questionController = TextEditingController();
    final optionControllers = [
      TextEditingController(),
      TextEditingController(),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Poll'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: questionController,
                  decoration: const InputDecoration(
                    labelText: 'Question',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ...optionControllers.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: entry.value,
                      decoration: InputDecoration(
                        labelText: 'Option ${entry.key + 1}',
                        border: const OutlineInputBorder(),
                        suffixIcon: optionControllers.length > 2
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setDialogState(
                                  () => optionControllers.removeAt(entry.key),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setDialogState(
                    () => optionControllers.add(TextEditingController()),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add option'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final question = questionController.text.trim();
                final options = optionControllers
                    .map((c) => c.text.trim())
                    .where((o) => o.isNotEmpty)
                    .toList();
                if (question.isEmpty || options.length < 2) return;
                Navigator.pop(ctx);
                ref
                    .read(messagesProvider(widget.groupId).notifier)
                    .sendPoll(question, options);
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionSuggestions(ThemeData theme) {
    if (!_showMentions || _mentionCandidates.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _mentionCandidates.length,
        itemBuilder: (context, index) {
          final member = _mentionCandidates[index];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundImage: member.picture != null
                  ? NetworkImage(member.picture!)
                  : null,
              child: member.picture == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            title: Text(
              member.displayName ?? member.pubkeyHex.substring(0, 16),
              style: const TextStyle(fontSize: 14),
            ),
            onTap: () => _insertMention(member),
          );
        },
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme, MessagesNotifier notifier) {
    final typing = notifier.typingPubkeys;
    if (typing.isEmpty) return const SizedBox.shrink();

    final names = typing.map((pk) {
      final profile = ref.watch(memberProfileProvider(pk));
      return profile.value?.displayName ??
          profile.value?.name ??
          '${pk.substring(0, 8)}...';
    }).toList();

    final text = names.length == 1
        ? '${names[0]} is typing...'
        : '${names.join(', ')} are typing...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface.withAlpha(120),
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
              _attachmentMenuItem(
                icon: Icons.poll_outlined,
                label: 'Poll',
                value: 'poll',
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

          // Text field or recording indicator
          Expanded(
            child: _isRecording
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Recording... ${_formatDuration(_recordingSeconds)}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
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
                        onChanged: (text) {
                          setState(() {});
                          ref
                              .read(messagesProvider(widget.groupId).notifier)
                              .onTyping();
                          _checkForMention(text);
                        },
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
                : _isRecording
                ? Row(
                    key: const ValueKey('recording'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: _cancelRecording,
                        tooltip: 'Cancel recording',
                      ),
                      Text(
                        _formatDuration(_recordingSeconds),
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          Icons.send,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: _isSending ? null : _stopAndSendVoiceMessage,
                        tooltip: 'Send voice message',
                      ),
                    ],
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
      case 'poll':
        _showCreatePollDialog();
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

  Future<void> _onVoiceMessage() async {
    if (_isRecording) {
      await _stopAndSendVoiceMessage();
      return;
    }

    // Check microphone permission
    if (!await _audioRecorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    // Start recording
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds++);
    });
  }

  Future<void> _stopAndSendVoiceMessage() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);

    if (path == null) return;

    final file = File(path);
    if (!file.existsSync()) return;

    final bytes = await file.readAsBytes();

    setState(() => _isSending = true);
    try {
      final result = await MediaAttachmentService.sendMediaMessage(
        groupId: widget.groupId,
        fileData: bytes,
        mimeType: 'audio/mp4',
        filename: 'voice_message.m4a',
      );
      ref
          .read(messagesProvider(widget.groupId).notifier)
          .addIncomingMessage(result.message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice message: ${_mediaError(e)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      // Clean up temp file
      file.delete().catchError((_) => file);
    }

    _recordingSeconds = 0;
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final path = await _audioRecorder.stop();
    if (path != null) File(path).delete().catchError((_) => File(path));
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
        setState(() {
          _isSearching = true;
          _searchQuery = '';
          _searchMatchIndices = [];
          _currentMatchIndex = -1;
          _searchController.clear();
        });
      case 'mute':
        final wasMuted = (ref.read(muteProvider).value ?? {}).contains(groupId);
        ref.read(muteProvider.notifier).toggle(groupId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasMuted ? 'Notifications unmuted' : 'Notifications muted',
            ),
          ),
        );
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
