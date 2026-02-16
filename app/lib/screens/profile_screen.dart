import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/relay_provider.dart';
import 'package:burrow_app/providers/profile_provider.dart';
import 'package:burrow_app/src/rust/api/identity.dart';
import 'package:burrow_app/src/rust/api/keypackage.dart' as rust_kp;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;
  bool _publishingKeyPackage = false;
  bool _showNsec = false;
  String? _nsec;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await setProfile(
        profile: ProfileData(displayName: name, name: name),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    setState(() => _saving = false);
  }

  Future<void> _republishKeyPackage() async {
    setState(() => _publishingKeyPackage = true);
    try {
      final relays = await rust_relay.listRelays();
      final urls = relays.where((r) => r.connected).map((r) => r.url).toList();
      if (urls.isEmpty) {
        urls.addAll(rust_relay.defaultRelayUrls());
      }
      await rust_kp.publishKeyPackage(relayUrls: urls);
      await rust_kp.publishKeyPackageRelays(relayUrls: urls);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Key package published')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error publishing key package: $e')),
        );
      }
    }
    setState(() => _publishingKeyPackage = false);
  }

  Future<void> _loadNsec() async {
    try {
      final nsec = await exportNsec();
      setState(() {
        _nsec = nsec;
        _showNsec = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading nsec: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final relays = ref.watch(relayProvider);

    final npub = auth.value?.account.npub ?? '...';
    final profile = ref.watch(selfProfileProvider);

    // Pre-populate display name from profile if field is empty
    if (_nameController.text.isEmpty && profile.value?.displayName != null) {
      _nameController.text = profile.value!.displayName!;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logoutUser();
              if (context.mounted) context.go('/onboarding');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // User avatar from Nostr profile
          Center(
            child: Builder(
              builder: (context) {
                final profile = ref.watch(selfProfileProvider);
                final pictureUrl = profile.value?.picture;
                return CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: pictureUrl != null && pictureUrl.isNotEmpty
                      ? NetworkImage(pictureUrl)
                      : null,
                  child: pictureUrl != null && pictureUrl.isNotEmpty
                      ? null
                      : Icon(
                          Icons.person,
                          size: 40,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // npub display
          Text('Public Key', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    npub,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: npub));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied npub!')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // nsec display (hidden by default)
          Text('Secret Key', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _showNsec && _nsec != null
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          _nsec!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _nsec!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied nsec!')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility_off, size: 18),
                        onPressed: () => setState(() => _showNsec = false),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tap to reveal your secret key',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loadNsec,
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('Reveal'),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            'Never share your secret key. Anyone with it can control your identity.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 24),

          // Display name edit
          Text('Display Name', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter display name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Republish key package
          Text('Key Package', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            'Other users need your key package to send you group invites. '
            'Republish if invites are not working.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _publishingKeyPackage ? null : _republishKeyPackage,
              icon: _publishingKeyPackage
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish, size: 18),
              label: Text(
                _publishingKeyPackage
                    ? 'Publishing...'
                    : 'Republish Key Package',
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Relay management
          Text('Relays', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          relays.when(
            data: (list) => Column(
              children: [
                ...list.map(
                  (r) => ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.circle,
                      size: 10,
                      color: r.connected ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      r.url,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          ref.read(relayProvider.notifier).remove(r.url),
                    ),
                  ),
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No relays configured',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
          TextButton.icon(
            onPressed: () => _showAddRelayDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add relay'),
          ),
        ],
      ),
    );
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
            onPressed: () {
              final url = controller.text.trim();
              if (url.startsWith('wss://')) {
                ref.read(relayProvider.notifier).addAndConnect(url);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
