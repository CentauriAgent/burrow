import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/contacts_provider.dart';
import 'package:burrow_app/screens/chat_shell_screen.dart';
import 'package:burrow_app/utils/dm_utils.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPubkey = null);
    }
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
                  Icon(Icons.contacts_outlined, size: 64,
                      color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('No contacts yet', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Contacts appear here when you join groups with other members.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
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
                    ? Icon(Icons.person,
                        color: theme.colorScheme.onTertiaryContainer)
                    : null,
              ),
              title: Text(contact.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_shortenKey(contact.pubkeyHex),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: isLoading ? null : () => _onContactTap(contact),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
