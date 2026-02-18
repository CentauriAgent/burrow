import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/archive_provider.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/group_avatar_provider.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/profile_provider.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/screens/chat_view_screen.dart';
import 'package:burrow_app/screens/group_info_screen.dart';
import 'package:burrow_app/screens/invite_members_screen.dart';
import 'package:burrow_app/widgets/contacts_list.dart';
import 'package:burrow_app/widgets/tab_aware_fab.dart';

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
class ChatShellScreen extends ConsumerStatefulWidget {
  final String? initialGroupId;
  const ChatShellScreen({super.key, this.initialGroupId});

  @override
  ConsumerState<ChatShellScreen> createState() => _ChatShellScreenState();
}

class _ChatShellScreenState extends ConsumerState<ChatShellScreen> {
  double _leftPaneWidth = 340;
  static const double _minLeftWidth = 240;
  static const double _maxLeftWidth = 500;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 700;

    if (widget.initialGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = ref.read(detailPaneProvider);
        if (current.groupId != widget.initialGroupId) {
          ref
              .read(detailPaneProvider.notifier)
              .selectChat(widget.initialGroupId!);
        }
      });
    }

    if (!isWide) {
      if (widget.initialGroupId != null) {
        return ChatViewScreen(groupId: widget.initialGroupId!);
      }
      return const _LeftPane(isWide: false);
    }

    // Clamp to available width
    final clampedWidth = _leftPaneWidth.clamp(
      _minLeftWidth,
      (width - 300).clamp(_minLeftWidth, _maxLeftWidth),
    );

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: clampedWidth,
            child: Material(elevation: 1, child: _LeftPane(isWide: true)),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _leftPaneWidth = (_leftPaneWidth + details.delta.dx).clamp(
                    _minLeftWidth,
                    (width - 300).clamp(_minLeftWidth, _maxLeftWidth),
                  );
                });
              },
              child: Container(
                width: 6,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withAlpha(80),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Expanded(child: _DetailPane()),
        ],
      ),
    );
  }
}

/// Left pane: tabbed Chats + Contacts.
class _LeftPane extends ConsumerStatefulWidget {
  final bool isWide;
  const _LeftPane({required this.isWide});

  @override
  ConsumerState<_LeftPane> createState() => _LeftPaneState();
}

class _LeftPaneState extends ConsumerState<_LeftPane>
    with SingleTickerProviderStateMixin {
  int _tabIndex = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _tabIndex = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);
    final pendingCount = ref.watch(pendingInviteCountProvider);
    final theme = Theme.of(context);

    final appBar = AppBar(
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
      bottom: widget.isWide
          ? TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Chats'),
                Tab(text: 'Contacts'),
              ],
            )
          : null,
    );

    final body = widget.isWide
        ? TabBarView(
            controller: _tabController,
            children: [
              _ChatListBody(isWide: true),
              ContactsListBody(isWide: true),
            ],
          )
        : IndexedStack(
            index: _tabIndex,
            children: [
              _ChatListBody(isWide: false),
              ContactsListBody(isWide: false),
            ],
          );

    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: TabAwareFab(tabIndex: _tabIndex),
      bottomNavigationBar: widget.isWide
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() {
                _tabIndex = i;
                _tabController.animateTo(i);
              }),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Chats',
                ),
                NavigationDestination(
                  icon: Icon(Icons.contacts_outlined),
                  selectedIcon: Icon(Icons.contacts),
                  label: 'Contacts',
                ),
              ],
            ),
    );
  }
}

/// The chat list body, extracted from the old _ChatListPane.
class _ChatListBody extends ConsumerWidget {
  final bool isWide;
  const _ChatListBody({required this.isWide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupProvider);
    final selectedId = ref.watch(selectedChatProvider);
    final theme = Theme.of(context);

    return groups.when(
      data: (_) {
        final list = ref.watch(visibleGroupsProvider);
        final archivedCount = ref.watch(archivedGroupCountProvider);

        if (list.isEmpty && archivedCount == 0) {
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
            itemCount: list.length + (archivedCount > 0 ? 1 : 0),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              // Archived groups row at the bottom
              if (index == list.length) {
                return ListTile(
                  leading: Icon(
                    Icons.archive_outlined,
                    color: theme.colorScheme.onSurface.withAlpha(150),
                  ),
                  title: Text(
                    'Archived ($archivedCount)',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                  onTap: () => context.push('/archived'),
                );
              }

              final group = list[index];
              final isSelected = group.mlsGroupIdHex == selectedId;
              final avatarState = ref.watch(
                groupAvatarProvider(group.mlsGroupIdHex),
              );
              return Dismissible(
                key: ValueKey(group.mlsGroupIdHex),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.archive_outlined,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                confirmDismiss: (_) async {
                  await ref
                      .read(archiveProvider.notifier)
                      .archive(group.mlsGroupIdHex);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${group.name.isNotEmpty ? group.name : "Group"} archived',
                        ),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => ref
                              .read(archiveProvider.notifier)
                              .unarchive(group.mlsGroupIdHex),
                        ),
                      ),
                    );
                  }
                  return false; // Don't remove widget, provider handles it
                },
                child: ListTile(
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withAlpha(60),
                  leading: CircleAvatar(
                    key: avatarState.avatarFile != null
                        ? ValueKey(
                            '${avatarState.avatarFile!.path}_${avatarState.version}',
                          )
                        : group.isDirectMessage && group.dmPeerPicture != null
                        ? ValueKey(group.dmPeerPicture)
                        : null,
                    backgroundColor: group.isDirectMessage
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.primaryContainer,
                    backgroundImage: avatarState.avatarFile != null
                        ? FileImage(avatarState.avatarFile!)
                        : group.isDirectMessage && group.dmPeerPicture != null
                        ? NetworkImage(group.dmPeerPicture!)
                        : null,
                    child:
                        (avatarState.avatarFile != null ||
                            (group.isDirectMessage &&
                                group.dmPeerPicture != null))
                        ? null
                        : group.isDirectMessage
                        ? Icon(
                            Icons.person,
                            color: theme.colorScheme.onTertiaryContainer,
                          )
                        : Icon(
                            Icons.group,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                  ),
                  title: Text(
                    group.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    group.isDirectMessage
                        ? 'Encrypted direct message'
                        : group.description.isNotEmpty
                        ? group.description
                        : '${group.state} · epoch ${group.epoch}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    Icons.circle,
                    size: 10,
                    color: group.state == 'active'
                        ? Colors.green
                        : Colors.grey,
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
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
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
