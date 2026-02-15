import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/providers/archive_provider.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/group_avatar_provider.dart';

class ArchivedGroupsScreen extends ConsumerWidget {
  const ArchivedGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedGroupsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Archived')),
      body: archived.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No archived chats',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: archived.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final group = archived[index];
                final avatarState = ref.watch(
                  groupAvatarProvider(group.mlsGroupIdHex),
                );
                final isInactive = group.state == 'inactive';

                return Dismissible(
                  key: ValueKey(group.mlsGroupIdHex),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.unarchive_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  confirmDismiss: (_) async {
                    await ref
                        .read(archiveProvider.notifier)
                        .unarchive(group.mlsGroupIdHex);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${group.name.isNotEmpty ? group.name : "Group"} unarchived',
                          ),
                        ),
                      );
                    }
                    return false;
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: avatarState.avatarFile != null
                          ? FileImage(avatarState.avatarFile!)
                          : null,
                      child: avatarState.avatarFile != null
                          ? null
                          : Icon(
                              Icons.group,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                    ),
                    title: Text(
                      group.name.isNotEmpty ? group.name : 'Unnamed Group',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      isInactive
                          ? 'Left group'
                          : group.description.isNotEmpty
                          ? group.description
                          : 'Archived',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isInactive
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.unarchive_outlined,
                              size: 20,
                            ),
                            tooltip: 'Unarchive',
                            onPressed: () {
                              ref
                                  .read(archiveProvider.notifier)
                                  .unarchive(group.mlsGroupIdHex);
                            },
                          ),
                    onTap: isInactive
                        ? null
                        : () {
                            ref
                                .read(archiveProvider.notifier)
                                .unarchive(group.mlsGroupIdHex);
                            context.go('/chat/${group.mlsGroupIdHex}');
                          },
                  ),
                );
              },
            ),
    );
  }
}
