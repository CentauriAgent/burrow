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
    if (tabIndex == 1) {
      return FloatingActionButton(
        onPressed: () => context.push('/new-dm'),
        tooltip: 'New Message',
        child: const Icon(Icons.message),
      );
    }
    return FloatingActionButton(
      onPressed: () => context.push('/create-group'),
      tooltip: 'Create Group',
      child: const Icon(Icons.group_add),
    );
  }
}
