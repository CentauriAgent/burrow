import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/src/rust/api/error.dart';

class InviteMembersScreen extends ConsumerStatefulWidget {
  final String groupId;
  const InviteMembersScreen({super.key, required this.groupId});

  @override
  ConsumerState<InviteMembersScreen> createState() =>
      _InviteMembersScreenState();
}

class _InviteMembersScreenState extends ConsumerState<InviteMembersScreen> {
  final _npubController = TextEditingController();
  final List<_InviteEntry> _invitees = [];
  bool _sending = false;

  @override
  void dispose() {
    _npubController.dispose();
    super.dispose();
  }

  /// Validate and add an npub/hex pubkey to the invite list.
  void _addInvitee() {
    final input = _npubController.text.trim();
    if (input.isEmpty) return;

    // Basic validation: npub1... (63 chars) or 64-char hex
    final isNpub = input.startsWith('npub1') && input.length == 63;
    final isHex = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(input);

    if (!isNpub && !isHex) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a valid npub or hex public key')),
      );
      return;
    }

    // Check duplicate
    if (_invitees.any((e) => e.input == input)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already added')),
      );
      return;
    }

    setState(() {
      _invitees.add(_InviteEntry(input: input, isHex: isHex));
      _npubController.clear();
    });
  }

  /// Paste from clipboard.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _npubController.text = data.text!.trim();
    }
  }

  /// Send invites to all added members.
  Future<void> _sendInvites() async {
    if (_invitees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one member to invite')),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      final inviteNotifier = ref.read(inviteProvider.notifier);
      final keyPackageJsons = <String>[];

      // Fetch key packages for each invitee
      for (final invitee in _invitees) {
        setState(() => invitee.status = _InviteStatus.fetching);

        try {
          // TODO: convert npub to hex if needed
          final pubkeyHex = invitee.isHex
              ? invitee.input
              : invitee.input; // npub→hex conversion needed

          final kpJson =
              await inviteNotifier.fetchUserKeyPackage(pubkeyHex);
          keyPackageJsons.add(kpJson);
          setState(() => invitee.status = _InviteStatus.ready);
        } catch (e) {
          setState(() {
            invitee.status = _InviteStatus.error;
            if (e is BurrowError) {
              final msg = e.message;
              if (msg.toLowerCase().contains('key package') ||
                  msg.toLowerCase().contains('keypackage') ||
                  msg.toLowerCase().contains('not found')) {
                invitee.error =
                    "Could not find user's encryption key. They may need to publish their KeyPackage first.";
              } else {
                invitee.error = msg;
              }
            } else {
              invitee.error = e.toString();
            }
          });
        }
      }

      // Only proceed if we got at least one key package
      if (keyPackageJsons.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Could not fetch KeyPackages for any invitee')),
          );
        }
        setState(() => _sending = false);
        return;
      }

      // Send the invites
      await inviteNotifier.sendInvite(
        mlsGroupIdHex: widget.groupId,
        keyPackageEventsJson: keyPackageJsons,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Invited ${keyPackageJsons.length} member(s)!')),
        );
        // Refresh group data and go to group info
        ref.read(groupProvider.notifier).refresh();
        context.go('/group-info/${widget.groupId}');
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e is BurrowError ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $errorMsg')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite Members'),
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Input area
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add people by their Nostr public key',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _npubController,
                        decoration: InputDecoration(
                          hintText: 'npub1... or hex pubkey',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: const Icon(Icons.person_add, size: 20),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste, size: 20),
                            onPressed: _pasteFromClipboard,
                            tooltip: 'Paste',
                          ),
                        ),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        onSubmitted: (_) => _addInvitee(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addInvitee,
                      icon: const Icon(Icons.add),
                      tooltip: 'Add',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Invitee list
          Expanded(
            child: _invitees.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_add_outlined,
                            size: 48,
                            color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('No members added yet',
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          'Paste an npub or hex pubkey above',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _invitees.length,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) {
                      final entry = _invitees[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              theme.colorScheme.secondaryContainer,
                          child: Text(
                            entry.input.substring(0, 2).toUpperCase(),
                            style: TextStyle(
                                color: theme
                                    .colorScheme.onSecondaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          _truncateKey(entry.input),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                        ),
                        subtitle: _buildStatusText(entry),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _sending
                              ? null
                              : () {
                                  setState(
                                      () => _invitees.removeAt(index));
                                },
                        ),
                      );
                    },
                  ),
          ),

          // Send button
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed:
                  _sending || _invitees.isEmpty ? null : _sendInvites,
              icon: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_sending
                  ? 'Sending invites...'
                  : 'Send Invite${_invitees.length > 1 ? 's' : ''} (${_invitees.length})'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildStatusText(_InviteEntry entry) {
    switch (entry.status) {
      case _InviteStatus.pending:
        return null;
      case _InviteStatus.fetching:
        return const Text('Fetching KeyPackage...',
            style: TextStyle(fontSize: 11, color: Colors.amber));
      case _InviteStatus.ready:
        return const Text('Ready',
            style: TextStyle(fontSize: 11, color: Colors.green));
      case _InviteStatus.error:
        return Text('Error: ${entry.error ?? "Unknown"}',
            style: const TextStyle(fontSize: 11, color: Colors.red));
    }
  }

  String _truncateKey(String key) {
    if (key.length > 20) {
      return '${key.substring(0, 12)}...${key.substring(key.length - 8)}';
    }
    return key;
  }
}

enum _InviteStatus { pending, fetching, ready, error }

class _InviteEntry {
  final String input;
  final bool isHex;
  _InviteStatus status;
  String? error;

  _InviteEntry({
    required this.input,
    required this.isHex,
    this.status = _InviteStatus.pending,
  });
}
