import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/screens/chat_view_screen.dart';

/// Notifier tracking which chat is currently selected in the split view.
class SelectedChatNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? groupId) => state = groupId;
}

final selectedChatProvider = NotifierProvider<SelectedChatNotifier, String?>(
  SelectedChatNotifier.new,
);

/// Desktop split-pane layout: chat list on the left, chat view on the right.
/// On narrow screens, this just shows the chat list (home_screen behavior).
class ChatShellScreen extends ConsumerWidget {
  /// If a groupId is passed via route, open that chat immediately.
  final String? initialGroupId;
  const ChatShellScreen({super.key, this.initialGroupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 700;

    // If navigated with a groupId, set it as selected
    if (initialGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedChatProvider.notifier).select(initialGroupId);
      });
    }

    if (!isWide) {
      // Narrow: if we have a selected chat from route, show it full screen
      if (initialGroupId != null) {
        return ChatViewScreen(groupId: initialGroupId!);
      }
      return const _ChatListPane(isWide: false);
    }

    // Wide: split pane
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Material(elevation: 1, child: _ChatListPane(isWide: true)),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: _ChatDetailPane()),
        ],
      ),
    );
  }
}

/// Left pane: chat list with app bar, FAB, groups.
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
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/profile'),
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
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withAlpha(60),
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
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
                          .read(selectedChatProvider.notifier)
                          .select(group.mlsGroupIdHex);
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

/// Right pane: shows the selected chat or an empty state.
class _ChatDetailPane extends ConsumerWidget {
  const _ChatDetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedChatProvider);
    final theme = Theme.of(context);

    if (selectedId == null) {
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

    return ChatViewScreen(key: ValueKey(selectedId), groupId: selectedId);
  }
}
