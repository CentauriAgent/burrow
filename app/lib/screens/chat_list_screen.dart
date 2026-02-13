import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/widgets/chat_list_tile.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  int _navIndex = 0;
  final _searchController = TextEditingController();
  bool _showSearch = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _buildAppBar(theme),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildChatsList(theme),
          _buildPlaceholderTab(theme, Icons.contacts_outlined, 'Contacts',
              'Contact list coming soon'),
          _buildPlaceholderTab(
              theme, Icons.call_outlined, 'Calls', 'Voice & video calls coming soon'),
          _buildSettingsTab(theme),
        ],
      ),
      floatingActionButton: _navIndex == 0
          ? FloatingActionButton(
              onPressed: _showNewChatDialog,
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
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
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    if (_showSearch) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _showSearch = false;
              _searchQuery = '';
              _searchController.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search conversations...',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        ),
      );
    }

    return AppBar(
      title: const Text('Burrow'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _showSearch = true),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.go('/profile'),
        ),
      ],
    );
  }

  Widget _buildChatsList(ThemeData theme) {
    final groups = ref.watch(sortedGroupsProvider);

    // Filter by search query
    final filtered = _searchQuery.isEmpty
        ? groups
        : groups
            .where((g) =>
                g.name.toLowerCase().contains(_searchQuery) ||
                (g.lastMessage?.toLowerCase().contains(_searchQuery) ?? false))
            .toList();

    if (groups.isEmpty) {
      return _buildEmptyState(theme);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(groupsProvider.notifier).refresh(),
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 80,
          color: theme.colorScheme.outlineVariant.withAlpha(50),
        ),
        itemBuilder: (context, index) {
          final group = filtered[index];
          return ChatListTile(
            name: group.name,
            lastMessage: group.lastMessage,
            lastMessageTime: group.lastMessageTime,
            unreadCount: group.unreadCount,
            memberCount: group.memberCount,
            onTap: () => context.go('/chat/${group.mlsGroupIdHex}'),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 72, color: theme.colorScheme.primary.withAlpha(150)),
            const SizedBox(height: 20),
            Text(
              'No conversations yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a new encrypted conversation\nusing the button below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _showNewChatDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Conversation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab(
      ThemeData theme, IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.primary.withAlpha(120)),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(subtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(120))),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ThemeData theme) {
    final auth = ref.watch(authProvider);
    final npub = auth.valueOrNull?.account.npub ?? '';

    return ListView(
      children: [
        const SizedBox(height: 16),
        ListTile(
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
          ),
          title: const Text('Profile'),
          subtitle: npub.isNotEmpty
              ? Text(
                  '${npub.substring(0, 16)}...',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                )
              : null,
          onTap: () => context.go('/profile'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Appearance'),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Relays'),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Privacy & Security'),
          onTap: () {},
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.info_outline, color: theme.colorScheme.onSurface.withAlpha(150)),
          title: const Text('About Burrow'),
          subtitle: Text('Marmot Protocol • End-to-end encrypted',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
          onTap: () {},
        ),
      ],
    );
  }

  void _showNewChatDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('New Conversation',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: const Icon(Icons.person_add_outlined),
                ),
                title: const Text('New Direct Message'),
                subtitle: const Text('Start a 1:1 encrypted chat'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to contact picker / npub entry
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: const Icon(Icons.group_add_outlined),
                ),
                title: const Text('New Group'),
                subtitle: const Text('Create an encrypted group chat'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to group creation flow
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
