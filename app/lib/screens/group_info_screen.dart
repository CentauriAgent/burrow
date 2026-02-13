import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart';
import 'package:burrow_app/src/rust/api/invite.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  GroupInfo? _group;
  List<MemberInfo>? _members;
  bool _loading = true;
  bool _leaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
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
      if (mounted) {
        setState(() {
          _group = group;
          _members = members;
          _loading = false;
        });
      }
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
        appBar: AppBar(title: const Text('Group Info')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Info')),
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
      appBar: AppBar(
        title: Text(group.name.isNotEmpty ? group.name : 'Group Info'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Invite members',
              onPressed: () => context.go('/invite/${widget.groupId}'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Group header
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.group,
                size: 36,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: isAdmin ? _editGroupName : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.name.isNotEmpty ? group.name : 'Unnamed Group',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 16, color: Colors.grey),
                  ],
                ],
              ),
            ),
          ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                group.description,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: Chip(
              avatar: Icon(
                group.state == 'active' ? Icons.check_circle : Icons.pending,
                size: 16,
                color: group.state == 'active' ? Colors.green : Colors.amber,
              ),
              label: Text(
                '${group.state} · epoch ${group.epoch}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Group ID
          Text('Group ID', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: group.nostrGroupIdHex));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Group ID copied')));
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _truncateHex(group.nostrGroupIdHex),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Icon(Icons.copy, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Members
          Row(
            children: [
              Text(
                'Members (${members.length})',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (isAdmin)
                TextButton.icon(
                  onPressed: () => context.go('/invite/${widget.groupId}'),
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...members.map((m) {
            final isSelf =
                m.pubkeyHex == ref.read(authProvider).value?.account.pubkeyHex;
            final isMemberAdmin = group.adminPubkeys.contains(m.pubkeyHex);

            final memberName = m.displayName ?? _truncateHex(m.pubkeyHex);
            final initials = m.displayName != null && m.displayName!.isNotEmpty
                ? m.displayName!.substring(0, 1).toUpperCase()
                : m.pubkeyHex.substring(0, 2).toUpperCase();

            return ListTile(
              dense: true,
              leading: m.picture != null
                  ? CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(m.picture!),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      memberName,
                      style: m.displayName != null
                          ? theme.textTheme.bodyMedium
                          : const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                    ),
                  ),
                  if (isSelf) ...[
                    const SizedBox(width: 6),
                    const Text(
                      '(you)',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
              ),
              subtitle: isMemberAdmin
                  ? const Text(
                      'Admin',
                      style: TextStyle(fontSize: 11, color: Colors.amber),
                    )
                  : null,
              trailing: isAdmin && !isSelf
                  ? IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      onPressed: () => _removeMember(m.pubkeyHex),
                      tooltip: 'Remove',
                    )
                  : null,
            );
          }),
          const SizedBox(height: 32),

          // Leave group
          OutlinedButton.icon(
            onPressed: _leaving ? null : _leaveGroup,
            icon: _leaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.exit_to_app, color: Colors.red),
            label: Text(
              _leaving ? 'Leaving...' : 'Leave Group',
              style: const TextStyle(color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}
