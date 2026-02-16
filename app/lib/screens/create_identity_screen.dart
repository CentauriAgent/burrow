import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/relay_provider.dart';
import 'package:burrow_app/src/rust/api/identity.dart';
import 'package:burrow_app/src/rust/api/keypackage.dart' as rust_kp;
import 'package:burrow_app/src/rust/api/relay.dart';

class CreateIdentityScreen extends ConsumerStatefulWidget {
  const CreateIdentityScreen({super.key});

  @override
  ConsumerState<CreateIdentityScreen> createState() =>
      _CreateIdentityScreenState();
}

class _CreateIdentityScreenState extends ConsumerState<CreateIdentityScreen> {
  final _displayNameController = TextEditingController();
  late List<String> _selectedRelays;
  bool _isCreating = false;
  String? _createdNpub;

  @override
  void initState() {
    super.initState();
    _selectedRelays = List.from(defaultRelayUrls());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _createIdentity() async {
    setState(() => _isCreating = true);
    try {
      final info = await ref.read(authProvider.notifier).createNewIdentity();

      // Set display name if provided
      final name = _displayNameController.text.trim();
      if (name.isNotEmpty) {
        await setProfile(
          profile: ProfileData(displayName: name, name: name),
        );
      }

      // Add relays
      final relayNotifier = ref.read(relayProvider.notifier);
      for (final url in _selectedRelays) {
        await relayNotifier.addAndConnect(url);
      }

      // Publish MLS key package to the user's selected relays so others can
      // find us and send group invites.
      try {
        await rust_kp.publishKeyPackage(relayUrls: _selectedRelays);
        await rust_kp.publishKeyPackageRelays(relayUrls: _selectedRelays);
      } catch (_) {
        // Non-fatal: key package will be re-published on next app launch.
      }

      setState(() {
        _createdNpub = info.npub;
        _isCreating = false;
      });
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Success state — show npub
    if (_createdNpub != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Identity Created')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('Your Identity', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'This is your public key. Share it freely.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    SelectableText(
                      _createdNpub!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _createdNpub!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied npub!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Continue to Burrow'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Creation form
    return Scaffold(
      appBar: AppBar(title: const Text('Create Identity')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Choose a display name', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Optional. You can change this anytime.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              hintText: 'Display name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),
          Text('Relays', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Connect to Nostr relays to communicate. Defaults work great.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          ..._selectedRelays.asMap().entries.map((entry) {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.dns_outlined, size: 20),
              title: Text(
                entry.value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() => _selectedRelays.removeAt(entry.key));
                },
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => _showAddRelayDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add relay'),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isCreating ? null : _createIdentity,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCreating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate Keypair & Create'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A cryptographic keypair will be generated on your device. '
            'Your private key never leaves this device.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
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
              if (url.startsWith('wss://') && !_selectedRelays.contains(url)) {
                setState(() => _selectedRelays.add(url));
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
