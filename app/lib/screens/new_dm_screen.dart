import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/utils/dm_utils.dart';

class NewDmScreen extends ConsumerStatefulWidget {
  const NewDmScreen({super.key});

  @override
  ConsumerState<NewDmScreen> createState() => _NewDmScreenState();
}

class _NewDmScreenState extends ConsumerState<NewDmScreen> {
  final _pubkeyController = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _pubkeyController.dispose();
    super.dispose();
  }

  /// Convert npub to hex, or validate hex pubkey.
  String? _parsePubkey(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // If it's an npub, try to decode (basic bech32 decode)
    if (trimmed.startsWith('npub1')) {
      // For now, accept npub as-is and let the Rust backend handle decoding.
      // A proper bech32 decode would go here.
      // Return the raw input so the backend can process it.
      return trimmed;
    }

    // Hex pubkey: 64 hex characters
    final hexRegex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (hexRegex.hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }

    return null;
  }

  Future<void> _startDm() async {
    final pubkey = _parsePubkey(_pubkeyController.text);
    if (pubkey == null) {
      setState(() => _error = 'Enter a valid npub or 64-character hex pubkey');
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final groupId = await findOrCreateDm(ref, pubkey);

      if (mounted) {
        context.go('/chat/$groupId');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _creating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Message')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start a direct message',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the Nostr public key of the person you want to message.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _pubkeyController,
              decoration: InputDecoration(
                labelText: 'Public Key',
                hintText: 'npub1... or hex pubkey',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                errorText: _error,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: 'Paste from clipboard',
                  onPressed: () async {
                    // Trigger paste via system
                  },
                ),
              ),
              maxLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _startDm(),
            ),
            const SizedBox(height: 8),
            Text(
              'Accepts npub (bech32) or 64-char hex format.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(100),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _creating ? null : _startDm,
              icon: _creating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_creating ? 'Creating...' : 'Start Chat'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
