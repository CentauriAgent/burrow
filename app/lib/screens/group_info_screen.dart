import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart';
import 'package:burrow_app/src/rust/api/invite.dart';
import 'package:burrow_app/src/rust/api/keypackage.dart' as rust_kp;
import 'package:burrow_app/services/user_service.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  GroupInfo? _group;
  List<MemberInfo>? _members;
  List<String> _groupRelays = [];
  bool _loading = true;
  bool _leaving = false;
  bool _updatingRelays = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _resolveProfiles(List<MemberInfo> members) async {
    bool updated = false;
    for (final m in members) {
      if (m.displayName == null) {
        try {
          final profile = await UserService(
            pubkeyHex: m.pubkeyHex,
          ).fetchProfile();
          final name = UserService.presentName(profile);
          if (name != null && mounted) updated = true;
        } catch (_) {}
      }
    }
    if (updated && mounted) {
      try {
        final refreshed = await ref
            .read(groupProvider.notifier)
            .getMembers(widget.groupId);
        if (mounted) setState(() => _members = refreshed);
      } catch (_) {}
    }
  }

  Future<void> _loadGroupInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groupNotifier = ref.read(groupProvider.notifier);
      final group = await groupNotifier.getGroupInfo(widget.groupId);
      final members = await groupNotifier.getMembers(widget.groupId);
      List<String> relays = [];
      try {
        relays = await getGroupRelays(mlsGroupIdHex: widget.groupId);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _group = group;
          _members = members;
          _groupRelays = relays;
          _loading = false;
        });
      }
      _resolveProfiles(members);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool _isAdmin() {
    final auth = ref.read(authProvider).value;
    if (auth == null || _group == null) return false;
    return _group!.adminPubkeys.contains(auth.account.pubkeyHex);
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text(
          'Leave "${_group?.name ?? 'this group'}"? You\'ll need a new invitation to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _leaving = true);
    try {
      await ref.read(groupProvider.notifier).leaveFromGroup(widget.groupId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Left group')));
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _leaving = false);
      }
    }
  }

  Future<void> _editGroupName() async {
    if (!_isAdmin()) return;
    final controller = TextEditingController(text: _group?.name ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Group Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != _group?.name) {
      try {
        await ref
            .read(groupProvider.notifier)
            .updateName(widget.groupId, newName);
        _loadGroupInfo();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _removeMember(String pubkeyHex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${_truncateHex(pubkeyHex)} from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await removeMembers(
        mlsGroupIdHex: widget.groupId,
        pubkeysHex: [pubkeyHex],
      );
      _loadGroupInfo();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addGroupRelay() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Relay'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'wss://relay.example.com',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('wss://') && !url.startsWith('ws://')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Relay URL must start with wss:// or ws://'),
          ),
        );
      }
      return;
    }
    final newRelays = [..._groupRelays, url];
    await _saveGroupRelays(newRelays);
  }

  Future<void> _removeGroupRelay(String url) async {
    final newRelays = _groupRelays.where((r) => r != url).toList();
    if (newRelays.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group must have at least one relay')),
        );
      }
      return;
    }
    await _saveGroupRelays(newRelays);
  }

  Future<void> _saveGroupRelays(List<String> relays) async {
    if (!_isAdmin()) return;
    setState(() => _updatingRelays = true);
    try {
      await updateGroupRelays(mlsGroupIdHex: widget.groupId, relayUrls: relays);
      await mergePendingCommit(mlsGroupIdHex: widget.groupId);
      await rust_kp.publishKeyPackage(relayUrls: relays);
      if (mounted) {
        setState(() => _groupRelays = relays);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Group relays updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _updatingRelays = false);
  }

  String _truncateHex(String hex) {
    if (hex.length > 16) {
      return '${hex.substring(0, 8)}...${hex.substring(hex.length - 8)}';
    }
    return hex;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _isAdmin();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Error loading group', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadGroupInfo,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final group = _group!;
    final members = _members ?? [];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with back button only
          SliverAppBar(
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.go('/chat/${widget.groupId}');
                }
              },
            ),
            title: null,
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                // --- Header: Avatar + Name + Description ---
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: isAdmin ? _editGroupName : null,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.group,
                      size: 40,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: isAdmin ? _editGroupName : null,
                  child: Text(
                    group.name.isNotEmpty ? group.name : 'Unnamed Group',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (group.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      group.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // --- Action buttons row (Signal-style) ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ActionButton(
                      icon: Icons.notifications_outlined,
                      label: 'Mute',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      ),
                    ),
                    const SizedBox(width: 24),
                    _ActionButton(
                      icon: Icons.search,
                      label: 'Search',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),

                // --- Group ID ---
                ListTile(
                  leading: const Icon(Icons.tag),
                  title: const Text('Group ID'),
                  subtitle: Text(
                    _truncateHex(group.nostrGroupIdHex),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: group.nostrGroupIdHex),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Group ID copied')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Encryption'),
                  subtitle: Text(
                    'MLS epoch ${group.epoch} · ${group.state}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Divider(),

                // --- Members section ---
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${members.length} members',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (isAdmin)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.add,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: const Text('Add members'),
                    onTap: () => context.push('/invite/${widget.groupId}'),
                  ),
                ...members.map((m) => _buildMemberTile(m, group, isAdmin)),
                const Divider(),

                // --- Relays section ---
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text(
                          'Relays',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_updatingRelays) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (isAdmin)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.add,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: const Text('Add relay'),
                    onTap: _updatingRelays ? null : _addGroupRelay,
                  ),
                if (_groupRelays.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.cloud_off, color: Colors.grey),
                    title: Text(
                      'No relays configured',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ..._groupRelays.map(
                  (url) => ListTile(
                    leading: Icon(
                      Icons.cloud_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      url,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    trailing: isAdmin
                        ? IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: _updatingRelays
                                ? null
                                : () => _removeGroupRelay(url),
                          )
                        : null,
                  ),
                ),
                const Divider(),

                // --- Leave group ---
                ListTile(
                  leading: Icon(
                    Icons.exit_to_app,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Leave group',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: _leaving ? null : _leaveGroup,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(MemberInfo m, GroupInfo group, bool isAdmin) {
    final theme = Theme.of(context);
    final isSelf =
        m.pubkeyHex == ref.read(authProvider).value?.account.pubkeyHex;
    final isMemberAdmin = group.adminPubkeys.contains(m.pubkeyHex);
    final memberName = m.displayName ?? _truncateHex(m.pubkeyHex);
    final initials = m.displayName != null && m.displayName!.isNotEmpty
        ? m.displayName!.substring(0, 1).toUpperCase()
        : m.pubkeyHex.substring(0, 2).toUpperCase();

    return ListTile(
      leading: m.picture != null
          ? CircleAvatar(
              backgroundImage: NetworkImage(m.picture!),
              backgroundColor: theme.colorScheme.secondaryContainer,
            )
          : CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(
                initials,
                style: TextStyle(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      title: Text(
        isSelf ? 'You' : memberName,
        style: m.displayName != null || isSelf
            ? null
            : const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMemberAdmin)
            Text(
              'Admin',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
            ),
          if (isAdmin && !isSelf)
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: Colors.red,
              ),
              onPressed: () => _removeMember(m.pubkeyHex),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withAlpha(80)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
