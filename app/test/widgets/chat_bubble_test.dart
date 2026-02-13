import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/widgets/chat_bubble.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ChatBubble', () {
    testWidgets('shows message content', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Hello world',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: false,
      )));

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('sent message shows checkmark', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Sent message',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: true,
      )));

      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('received message does not show checkmark', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Received message',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: false,
      )));

      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('shows sender name when enabled', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Group message',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: false,
        senderName: 'abc123de',
        showSenderName: true,
      )));

      expect(find.text('abc123de'), findsOneWidget);
    });

    testWidgets('hides sender name when showSenderName is false', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Group message',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: false,
        senderName: 'abc123de',
        showSenderName: false,
      )));

      expect(find.text('abc123de'), findsNothing);
    });

    testWidgets('sent bubble is right-aligned', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Right aligned',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: true,
      )));

      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('received bubble is left-aligned', (tester) async {
      await tester.pumpWidget(wrap(ChatBubble(
        content: 'Left aligned',
        timestamp: DateTime(2025, 1, 15, 14, 30),
        isSent: false,
      )));

      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerLeft);
    });
  });
}
