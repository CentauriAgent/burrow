import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/widgets/chat_list_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ChatListTile', () {
    testWidgets('shows group name', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(name: 'Test Group')));
      expect(find.text('Test Group'), findsOneWidget);
    });

    testWidgets('shows initials for single word name', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(name: 'Burrow')));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('shows initials for multi-word name', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(name: 'Dev Team')));
      expect(find.text('DT'), findsOneWidget);
    });

    testWidgets('shows last message', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(
        name: 'Chat',
        lastMessage: 'Hey there!',
      )));
      expect(find.text('Hey there!'), findsOneWidget);
    });

    testWidgets('shows member count when no messages', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(
        name: 'Chat',
        memberCount: 5,
      )));
      expect(find.text('5 members'), findsOneWidget);
    });

    testWidgets('shows unread badge', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(
        name: 'Chat',
        unreadCount: 3,
      )));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('caps unread at 99+', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(
        name: 'Chat',
        unreadCount: 150,
      )));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ChatListTile(
        name: 'Chat',
        onTap: () => tapped = true,
      )));
      await tester.tap(find.byType(ListTile));
      expect(tapped, isTrue);
    });

    testWidgets('shows "No messages yet" when no lastMessage and no members', (tester) async {
      await tester.pumpWidget(wrap(ChatListTile(name: 'Empty')));
      expect(find.text('No messages yet'), findsOneWidget);
    });
  });
}
