import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/invite_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider);
    final groups = ref.watch(groupProvider);
    final pendingCount = ref.watch(pendingInviteCountProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Burrow'),
        actions: [
          // Pending invites badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline),
                onPressed: () => context.go('/invites'),
                tooltip: 'Invitations',
              ),
              if (pendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$pendingCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/create-group'),
        tooltip: 'Create Group',
        child: const Icon(Icons.group_add),
      ),
      body: groups.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text('No groups yet', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Create a group or accept an invitation to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.go('/create-group'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Group'),
                    ),
                    if (pendingCount > 0) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/invites'),
                        icon: const Icon(Icons.mail),
                        label: Text(
                          '$pendingCount pending invite${pendingCount > 1 ? 's' : ''}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(groupProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: list.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final group = list[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.group,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    group.name.isNotEmpty ? group.name : 'Unnamed Group',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    group.description.isNotEmpty
                        ? group.description
                        : '${group.state} · epoch ${group.epoch}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    Icons.circle,
                    size: 10,
                    color: group.state == 'active' ? Colors.green : Colors.grey,
                  ),
                  onTap: () => context.go('/group-info/${group.mlsGroupIdHex}'),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
