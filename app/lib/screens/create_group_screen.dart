import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/relay_provider.dart';
import 'package:burrow_app/services/group_avatar_service.dart';

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
  File? _avatarImage;
  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group name is required')));
      return;
    }

    final auth = ref.read(authProvider).value;
    if (auth == null) return;

    setState(() => _creating = true);
    try {
      final relayUrls = _selectedRelays.isNotEmpty
          ? _selectedRelays.toList()
          : ref.read(relayProvider.notifier).defaultRelays;

      final result = await ref
          .read(groupProvider.notifier)
          .createNewGroup(
            name: name,
            description: _descController.text.trim(),
            adminPubkeysHex: [auth.account.pubkeyHex],
            relayUrls: relayUrls,
          );

      // Upload picked avatar to Blossom and update MLS extension
      if (_avatarImage != null) {
        try {
          final bytes = await _avatarImage!.readAsBytes();
          final mimeType = _avatarImage!.path.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg';
          await GroupAvatarService.uploadGroupAvatar(
            groupId: result.mlsGroupIdHex,
            imageData: bytes,
            mimeType: mimeType,
          );
        } catch (_) {
          // Avatar upload failed — group was still created successfully
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Group "$name" created!')));
        // Navigate to invite members for this new group
        context.go('/invite/${result.mlsGroupIdHex}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _creating = false);
  }

  void _showAddRelayDialog() {
    final controller = TextEditingController();
    showDialog(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.startsWith('wss://') || url.startsWith('ws://')) {
                Navigator.pop(ctx);
                await ref.read(relayProvider.notifier).addAndConnect(url);
                if (mounted) {
                  setState(() {
                    _selectedRelays.add(url);
                  });
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
              onTap: () async {
                final picked = await _imagePicker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 512,
                  maxHeight: 512,
                );
                if (picked != null) {
                  setState(() => _avatarImage = File(picked.path));
                }
              },
              child: CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: _avatarImage != null
                    ? FileImage(_avatarImage!)
                    : null,
                child: _avatarImage == null
                    ? Icon(
                        Icons.group_add,
                        size: 36,
                        color: theme.colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Tap to set avatar',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
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
          Text(
            'Select relays for group messages',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          relays.when(
            data: (list) {
              final defaultUrls = ref
                  .read(relayProvider.notifier)
                  .defaultRelays;
              if (list.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'No relays configured. Tap to add default relays:',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: defaultUrls.map((url) {
                        final isSelected = _selectedRelays.contains(url);
                        return FilterChip(
                          label: Text(
                            url,
                            style: const TextStyle(fontSize: 11),
                          ),
                          avatar: isSelected
                              ? const Icon(Icons.check, size: 16)
                              : const Icon(Icons.add, size: 16),
                          selected: isSelected,
                          onSelected: (_) async {
                            setState(() {
                              if (isSelected) {
                                _selectedRelays.remove(url);
                              } else {
                                _selectedRelays.add(url);
                              }
                            });
                            if (!isSelected) {
                              await ref
                                  .read(relayProvider.notifier)
                                  .addAndConnect(url);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _showAddRelayDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add custom relay'),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  ...list.map((r) {
                    final selected = _selectedRelays.contains(r.url);
                    return CheckboxListTile(
                      dense: true,
                      title: Text(
                        r.url,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
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
                  }),
                  TextButton.icon(
                    onPressed: _showAddRelayDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add relay'),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 32),

          // Create button
          FilledButton.icon(
            onPressed: _creating ? null : _createGroup,
            icon: _creating
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
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
