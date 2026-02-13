import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/group_avatar_provider.dart';
import 'package:burrow_app/providers/profile_provider.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/screens/chat_view_screen.dart';
import 'package:burrow_app/screens/group_info_screen.dart';
import 'package:burrow_app/screens/invite_members_screen.dart';

/// What the right pane is currently showing.
enum DetailView { chat, groupInfo, invite }

/// State for the right pane: which group + which view.
class DetailPaneState {
  final String? groupId;
  final DetailView view;

  const DetailPaneState({this.groupId, this.view = DetailView.chat});

  DetailPaneState copyWith({String? groupId, DetailView? view}) {
    return DetailPaneState(
      groupId: groupId ?? this.groupId,
      view: view ?? this.view,
    );
  }
}

class DetailPaneNotifier extends Notifier<DetailPaneState> {
  @override
  DetailPaneState build() => const DetailPaneState();

  void selectChat(String groupId) {
    state = DetailPaneState(groupId: groupId, view: DetailView.chat);
  }

  void showGroupInfo(String groupId) {
    state = DetailPaneState(groupId: groupId, view: DetailView.groupInfo);
  }

  void showInvite(String groupId) {
    state = DetailPaneState(groupId: groupId, view: DetailView.invite);
  }

  void backToChat() {
    if (state.groupId != null) {
      state = DetailPaneState(groupId: state.groupId, view: DetailView.chat);
    }
  }
}

final detailPaneProvider =
    NotifierProvider<DetailPaneNotifier, DetailPaneState>(
      DetailPaneNotifier.new,
    );

/// Convenience: just the selected group ID.
final selectedChatProvider = Provider<String?>((ref) {
  return ref.watch(detailPaneProvider).groupId;
});

/// Desktop split-pane layout: chat list on the left, chat/info/invite on the right.
/// On narrow screens, this just shows the chat list (mobile behavior).
class ChatShellScreen extends ConsumerWidget {
  final String? initialGroupId;
  const ChatShellScreen({super.key, this.initialGroupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 700;

    if (initialGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = ref.read(detailPaneProvider);
        if (current.groupId != initialGroupId) {
          ref.read(detailPaneProvider.notifier).selectChat(initialGroupId!);
        }
      });
    }

    if (!isWide) {
      if (initialGroupId != null) {
        return ChatViewScreen(groupId: initialGroupId!);
      }
      return const _ChatListPane(isWide: false);
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Material(elevation: 1, child: _ChatListPane(isWide: true)),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: _DetailPane()),
        ],
      ),
    );
  }
}

/// Left pane: chat list.
class _ChatListPane extends ConsumerWidget {
  final bool isWide;
  const _ChatListPane({required this.isWide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider);
    final groups = ref.watch(groupProvider);
    final pendingCount = ref.watch(pendingInviteCountProvider);
    final selectedId = ref.watch(selectedChatProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Burrow'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline),
                onPressed: () => context.push('/invites'),
                tooltip: 'Invitations',
              ),
              if (pendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$pendingCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => context.push('/profile'),
              child: Builder(
                builder: (context) {
                  final profile = ref.watch(selfProfileProvider);
                  final pictureUrl = profile.value?.picture;
                  return CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: pictureUrl != null && pictureUrl.isNotEmpty
                        ? NetworkImage(pictureUrl)
                        : null,
                    child: pictureUrl != null && pictureUrl.isNotEmpty
                        ? null
                        : Icon(
                            Icons.person,
                            size: 18,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-group'),
        tooltip: 'Create Group',
        child: const Icon(Icons.group_add),
      ),
      body: groups.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text('No groups yet', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Create a group or accept an invitation to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.push('/create-group'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Group'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(groupProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: list.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final group = list[index];
                final isSelected = group.mlsGroupIdHex == selectedId;
                final avatarState = ref.watch(
                  groupAvatarProvider(group.mlsGroupIdHex),
                );
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withAlpha(60),
                  leading: CircleAvatar(
                    key: avatarState.avatarFile != null
                        ? ValueKey(
                            '${avatarState.avatarFile!.path}_${avatarState.version}',
                          )
                        : null,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: avatarState.avatarFile != null
                        ? FileImage(avatarState.avatarFile!)
                        : null,
                    child: avatarState.avatarFile != null
                        ? null
                        : Icon(
                            Icons.group,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                  ),
                  title: Text(
                    group.name.isNotEmpty ? group.name : 'Unnamed Group',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    group.description.isNotEmpty
                        ? group.description
                        : '${group.state} · epoch ${group.epoch}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    Icons.circle,
                    size: 10,
                    color: group.state == 'active' ? Colors.green : Colors.grey,
                  ),
                  onTap: () {
                    if (isWide) {
                      ref
                          .read(detailPaneProvider.notifier)
                          .selectChat(group.mlsGroupIdHex);
                    } else {
                      context.go('/chat/${group.mlsGroupIdHex}');
                    }
                  },
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

/// Right pane: shows chat, group info, or invite based on detailPaneProvider.
class _DetailPane extends ConsumerWidget {
  const _DetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paneState = ref.watch(detailPaneProvider);
    final theme = Theme.of(context);

    if (paneState.groupId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/burrow.png', width: 80, height: 80),
            ),
            const SizedBox(height: 16),
            Text('Burrow', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Select a conversation to start messaging',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final groupId = paneState.groupId!;

    switch (paneState.view) {
      case DetailView.groupInfo:
        return GroupInfoScreen(
          key: ValueKey('info-$groupId'),
          groupId: groupId,
        );
      case DetailView.invite:
        return InviteMembersScreen(
          key: ValueKey('invite-$groupId'),
          groupId: groupId,
        );
      case DetailView.chat:
        return ChatViewScreen(key: ValueKey('chat-$groupId'), groupId: groupId);
    }
  }
}
