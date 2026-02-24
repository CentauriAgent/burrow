import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/contacts_provider.dart';
import 'package:burrow_app/screens/chat_shell_screen.dart';
import 'package:burrow_app/utils/dm_utils.dart';
import 'package:burrow_app/src/rust/api/contacts.dart' as rust_contacts;

/// The contacts tab body, used in both mobile and desktop layouts.
class ContactsListBody extends ConsumerStatefulWidget {
  final bool isWide;
  const ContactsListBody({super.key, required this.isWide});

  @override
  ConsumerState<ContactsListBody> createState() => _ContactsListBodyState();
}

class _ContactsListBodyState extends ConsumerState<ContactsListBody> {
  String? _loadingPubkey;

  String _shortenKey(String key) {
    if (key.length > 16) {
      return '${key.substring(0, 8)}...${key.substring(key.length - 8)}';
    }
    return key;
  }

  Future<void> _onContactTap(Contact contact) async {
    setState(() => _loadingPubkey = contact.pubkeyHex);
    try {
      final groupId = await findOrCreateDm(ref, contact.pubkeyHex);
      if (!mounted) return;
      if (widget.isWide) {
        ref.read(detailPaneProvider.notifier).selectChat(groupId);
      } else {
        context.go('/chat/$groupId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingPubkey = null);
    }
  }

  Future<void> _showContactOptions(Contact contact) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Send Message'),
              onTap: () => Navigator.pop(ctx, 'message'),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: const Text(
                'Unfollow',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, 'unfollow'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result == 'message') {
      _onContactTap(contact);
    } else if (result == 'unfollow') {
      try {
        await rust_contacts.unfollowContact(pubkeyHex: contact.pubkeyHex);
        ref.read(contactsProvider.notifier).refresh();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Unfollowed ${contact.name}')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _showDebug(BuildContext context) async {
    final debug = await rust_contacts.debugSyncContacts();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contacts Debug'),
        content: Text(
          'Connected relays: ${debug.connectedRelays}\n'
          'Follows from relay: ${debug.followCount}\n'
          'Key packages found: ${debug.keyPackageCount}\n'
          'DB follows: ${debug.dbFollowCount}\n'
          'DB with key pkg: ${debug.dbKpCount}\n'
          '${debug.error != null ? 'Error: ${debug.error}' : 'No errors'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final theme = Theme.of(context);

    return contacts.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.contacts_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text('No contacts yet', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Nostr follows using Marmot will appear here.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(contactsProvider.notifier).refresh(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync Contacts'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _showDebug(context),
                    child: const Text('Debug'),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${list.length} contact${list.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.sync, size: 20),
                    onPressed: () =>
                        ref.read(contactsProvider.notifier).refresh(),
                    tooltip: 'Sync contacts',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final contact = list[index];
                  final isLoading = _loadingPubkey == contact.pubkeyHex;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.tertiaryContainer,
                      backgroundImage: contact.picture != null
                          ? NetworkImage(contact.picture!)
                          : null,
                      child: contact.picture == null
                          ? Icon(
                              Icons.person,
                              color: theme.colorScheme.onTertiaryContainer,
                            )
                          : null,
                    ),
                    title: Text(
                      contact.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _shortenKey(contact.pubkeyHex),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: isLoading ? null : () => _onContactTap(contact),
                    onLongPress: () => _showContactOptions(contact),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load contacts', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(contactsProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
