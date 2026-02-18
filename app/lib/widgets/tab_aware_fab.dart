import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// FAB that changes icon/action based on the current tab index.
/// tabIndex 0 = Chats → Create Group
/// tabIndex 1 = Contacts → New Message
class TabAwareFab extends StatelessWidget {
  final int tabIndex;
  const TabAwareFab({super.key, required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    // Only show FAB on the Chats tab — contacts tab has tap-to-DM on each row.
    if (tabIndex != 0) return const SizedBox.shrink();
    return FloatingActionButton(
      onPressed: () => context.push('/create-group'),
      tooltip: 'Create Group',
      child: const Icon(Icons.group_add),
    );
  }
}
