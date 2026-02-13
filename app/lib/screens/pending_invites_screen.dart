import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';

class PendingInvitesScreen extends ConsumerWidget {
  const PendingInvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invites = ref.watch(inviteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(inviteProvider.notifier).refresh(),
          ),
        ],
      ),
      body: invites.when(
        data: (list) {
          final pending = list.where((w) => w.state == 'pending').toList();
          if (pending.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No pending invitations',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'When someone invites you to a group,\nit will appear here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(inviteProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: pending.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final invite = pending[index];
                return _InviteCard(invite: invite);
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

class _InviteCard extends ConsumerStatefulWidget {
  final dynamic invite; // WelcomeInfo
  const _InviteCard({required this.invite});

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _accepting = false;
  bool _declining = false;

  Future<void> _accept() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Group'),
        content: Text(
          'Join "${widget.invite.groupName}"? You\'ll become a member of this encrypted group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _accepting = true);
    try {
      await ref
          .read(inviteProvider.notifier)
          .acceptInvite(widget.invite.welcomeEventId);
      ref.read(groupProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined "${widget.invite.groupName}"!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _accepting = false);
  }

  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Invitation'),
        content: Text(
          'Decline the invitation to "${widget.invite.groupName}"? You can\'t undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _declining = true);
    try {
      await ref
          .read(inviteProvider.notifier)
          .declineInvite(widget.invite.welcomeEventId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation declined')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _declining = false);
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
    final invite = widget.invite;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group name and icon
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.group,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.groupName.isNotEmpty
                            ? invite.groupName
                            : 'Unnamed Group',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (invite.groupDescription.isNotEmpty)
                        Text(
                          invite.groupDescription,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Invite details
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'From: ${_truncateHex(invite.welcomerPubkeyHex)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${invite.memberCount} member${invite.memberCount != 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _accepting || _declining ? null : _decline,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: _declining
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _accepting || _declining ? null : _accept,
                  icon: _accepting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
