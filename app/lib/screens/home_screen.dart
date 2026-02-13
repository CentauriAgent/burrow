import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final npub = auth.valueOrNull?.account.npub ?? '';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Burrow 🦫'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('No conversations yet',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Encrypted group messaging is coming soon.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              if (npub.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  npub,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
