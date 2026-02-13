import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';

class ImportIdentityScreen extends ConsumerStatefulWidget {
  const ImportIdentityScreen({super.key});

  @override
  ConsumerState<ImportIdentityScreen> createState() =>
      _ImportIdentityScreenState();
}

class _ImportIdentityScreenState extends ConsumerState<ImportIdentityScreen> {
  final _nsecController = TextEditingController();
  bool _isImporting = false;
  bool _obscureKey = true;

  @override
  void dispose() {
    _nsecController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final key = _nsecController.text.trim();
    if (key.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await ref.read(authProvider.notifier).importIdentity(key);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _isImporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid key: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import Identity')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.key, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Enter your secret key',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Paste your nsec or hex private key. It stays on your device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nsecController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              hintText: 'nsec1...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          // QR scan placeholder
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('QR scanner coming soon')),
              );
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isImporting ? null : _import,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isImporting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Import & Login'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 20, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your private key is never sent to any server. '
                    'It is stored only on this device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
