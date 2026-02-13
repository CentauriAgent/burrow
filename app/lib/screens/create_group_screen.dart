import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/relay_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _creating = false;
  final Set<String> _selectedRelays = {};

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required')),
      );
      return;
    }

    final auth = ref.read(authProvider).value;
    if (auth == null) return;

    setState(() => _creating = true);
    try {
      final relayUrls = _selectedRelays.isNotEmpty
          ? _selectedRelays.toList()
          : ref.read(relayProvider.notifier).defaultRelays;

      final result = await ref.read(groupProvider.notifier).createNewGroup(
            name: name,
            description: _descController.text.trim(),
            adminPubkeysHex: [auth.account.pubkeyHex],
            relayUrls: relayUrls,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "$name" created!')),
        );
        // Navigate to invite members for this new group
        context.go('/invite/${result.mlsGroupIdHex}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relays = ref.watch(relayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Group')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Group avatar placeholder
          Center(
            child: GestureDetector(
              onTap: () {
                // TODO: avatar picker
              },
              child: CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.group_add, size: 36,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Tap to set avatar',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey)),
          ),
          const SizedBox(height: 24),

          // Group name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Group Name *',
              hintText: 'e.g. Nostr Devs',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.group),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What is this group about?',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.description_outlined),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),

          // Relay selection
          Text('Relays', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Select relays for group messages',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          relays.when(
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No relays configured. Default relays will be used.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: list.map((r) {
                  final selected = _selectedRelays.contains(r.url);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(r.url,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                    subtitle: Text(
                      r.connected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        fontSize: 11,
                        color: r.connected ? Colors.green : Colors.red,
                      ),
                    ),
                    value: selected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedRelays.add(r.url);
                        } else {
                          _selectedRelays.remove(r.url);
                        }
                      });
                    },
                  );
                }).toList(),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 32),

          // Create button
          FilledButton.icon(
            onPressed: _creating ? null : _createGroup,
            icon: _creating
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add),
            label: Text(_creating ? 'Creating...' : 'Create Group'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
