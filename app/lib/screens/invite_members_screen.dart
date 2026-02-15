import 'package:bech32/bech32.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/src/rust/api/error.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/invite.dart' as rust_invite;
import 'package:burrow_app/screens/chat_shell_screen.dart';
import 'package:burrow_app/services/user_service.dart';

/// Decode an npub1... bech32 string to a 64-char hex pubkey.
/// Returns null if decoding fails.
String? _npubToHex(String npub) {
  try {
    final decoded = Bech32Codec().decode(npub, npub.length);
    if (decoded.hrp != 'npub') return null;
    // Convert 5-bit words back to 8-bit bytes
    final words = decoded.data;
    final bytes = _convertBits(words, 5, 8, false);
    if (bytes == null || bytes.length != 32) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  } catch (_) {
    return null;
  }
}

/// Convert between bit groups (bech32 5-bit <-> 8-bit bytes).
List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
  int acc = 0;
  int bits = 0;
  final result = <int>[];
  final maxV = (1 << toBits) - 1;
  for (final value in data) {
    if (value < 0 || value >> fromBits != 0) return null;
    acc = (acc << fromBits) | value;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxV);
    }
  }
  if (pad) {
    if (bits > 0) {
      result.add((acc << (toBits - bits)) & maxV);
    }
  } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxV) != 0) {
    return null;
  }
  return result;
}

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
  Set<String> _existingMemberPubkeys = {};

  @override
  void initState() {
    super.initState();
    _loadExistingMembers();
  }

  Future<void> _loadExistingMembers() async {
    try {
      final members = await rust_group.getGroupMembers(
        mlsGroupIdHex: widget.groupId,
      );
      if (mounted) {
        setState(() {
          _existingMemberPubkeys = members.map((m) => m.pubkeyHex).toSet();
        });
      }
    } catch (_) {}
  }

  void _goBack(bool isWide) {
    if (isWide) {
      // In desktop split-pane, check if we're in the detail pane vs full-page
      final pane = ref.read(detailPaneProvider);
      if (pane.groupId != null) {
        ref.read(detailPaneProvider.notifier).showGroupInfo(widget.groupId);
      } else {
        context.go('/home');
      }
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      // Can't pop — likely navigated here directly (e.g., after group creation).
      // Go to the chat for this group, or home if that fails.
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _npubController.dispose();
    super.dispose();
  }

  /// Validate and add an npub/hex pubkey to the invite list.
  void _addInvitee() {
    final input = _npubController.text.trim();
    if (input.isEmpty) return;

    // Validate and resolve to hex
    String hexKey;
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(input)) {
      hexKey = input.toLowerCase();
    } else if (input.startsWith('npub1')) {
      final decoded = _npubToHex(input);
      if (decoded == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid npub format')));
        return;
      }
      hexKey = decoded;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid npub or hex public key')),
      );
      return;
    }

    // Check if already a group member
    if (_existingMemberPubkeys.contains(hexKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This user is already a member of this group'),
        ),
      );
      return;
    }

    // Check duplicate in current invite list (by resolved hex)
    if (_invitees.any((e) => e.hexKey == hexKey)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Already added')));
      return;
    }

    final entry = _InviteEntry(input: input, hexKey: hexKey);
    setState(() {
      _invitees.add(entry);
      _npubController.clear();
    });

    // Fetch profile in background
    _resolveProfile(entry);
  }

  Future<void> _resolveProfile(_InviteEntry entry) async {
    try {
      final profile = await UserService(pubkeyHex: entry.hexKey).fetchProfile();
      if (mounted) {
        setState(() {
          entry.displayName = UserService.presentName(profile);
          entry.picture = profile.picture;
        });
      }
    } catch (_) {}
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
          final pubkeyHex = invitee.hexKey;

          final kpJson = await inviteNotifier.fetchUserKeyPackage(pubkeyHex);
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
              content: Text('Could not fetch KeyPackages for any invitee'),
            ),
          );
        }
        setState(() => _sending = false);
        return;
      }

      // Send the invites (with retry on duplicate member)
      try {
        await inviteNotifier.sendInvite(
          mlsGroupIdHex: widget.groupId,
          keyPackageEventsJson: keyPackageJsons,
        );
      } catch (e) {
        final msg = e is BurrowError ? e.message : e.toString();
        if (msg.contains('Duplicate signature key') ||
            msg.contains('duplicate')) {
          // Member was added in a previous failed attempt — remove and retry
          for (final invitee in _invitees) {
            try {
              await rust_invite.removeMembers(
                mlsGroupIdHex: widget.groupId,
                pubkeysHex: [invitee.hexKey],
              );
            } catch (_) {}
          }
          // Retry the invite
          await inviteNotifier.sendInvite(
            mlsGroupIdHex: widget.groupId,
            keyPackageEventsJson: keyPackageJsons,
          );
        } else {
          rethrow;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invited ${keyPackageJsons.length} member(s)!'),
          ),
        );
        ref.read(groupProvider.notifier).refresh();
        final wide = MediaQuery.of(context).size.width >= 700;
        if (wide) {
          ref.read(detailPaneProvider.notifier).showGroupInfo(widget.groupId);
        } else {
          context.go('/group-info/${widget.groupId}');
        }
      }
    } catch (e) {
      if (mounted) {
        final raw = e is BurrowError ? e.message : e.toString();
        String errorMsg;
        if (raw.contains('EndOfStream') || raw.contains('tls_codec')) {
          errorMsg =
              'Invalid KeyPackage format. The user may not be using a Marmot-compatible app, or their KeyPackage is corrupted.';
        } else if (raw.contains('Duplicate signature key')) {
          errorMsg =
              'This member was already added. Try removing them from the group first, then re-invite.';
        } else {
          errorMsg = raw;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $errorMsg')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(isWide),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Invite Members'),
        actions: [
          TextButton(
            onPressed: () => _goBack(isWide),
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
                Text(
                  'Add people by their Nostr public key',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                ),
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
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
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
                        Icon(
                          Icons.group_add_outlined,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No members added yet',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Paste an npub or hex pubkey above',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _invitees.length,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) {
                      final entry = _invitees[index];
                      final hasName =
                          entry.displayName != null &&
                          entry.displayName!.isNotEmpty;
                      final initials = hasName
                          ? entry.displayName!.substring(0, 1).toUpperCase()
                          : entry.hexKey.substring(0, 2).toUpperCase();

                      return ListTile(
                        leading: entry.picture != null
                            ? CircleAvatar(
                                backgroundImage: NetworkImage(entry.picture!),
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                              )
                            : CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                        title: Text(
                          hasName
                              ? entry.displayName!
                              : _truncateKey(entry.input),
                          style: hasName
                              ? null
                              : const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                        ),
                        subtitle: _buildStatusText(entry),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _sending
                              ? null
                              : () {
                                  setState(() => _invitees.removeAt(index));
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
              onPressed: _sending || _invitees.isEmpty ? null : _sendInvites,
              icon: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _sending
                    ? 'Sending invites...'
                    : 'Send Invite${_invitees.length > 1 ? 's' : ''} (${_invitees.length})',
              ),
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
        return const Text(
          'Fetching KeyPackage...',
          style: TextStyle(fontSize: 11, color: Colors.amber),
        );
      case _InviteStatus.ready:
        return const Text(
          'Ready',
          style: TextStyle(fontSize: 11, color: Colors.green),
        );
      case _InviteStatus.error:
        return Text(
          'Error: ${entry.error ?? "Unknown"}',
          style: const TextStyle(fontSize: 11, color: Colors.red),
        );
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
  final String hexKey;
  _InviteStatus status = _InviteStatus.pending;
  String? error;
  String? displayName;
  String? picture;

  _InviteEntry({required this.input, required this.hexKey});
}
