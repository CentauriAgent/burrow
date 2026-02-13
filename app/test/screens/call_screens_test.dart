import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/screens/outgoing_call_screen.dart';

void main() {
  group('OutgoingCallScreen', () {
    testWidgets('renders cancel button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OutgoingCallScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Calling...'), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });
  });
}
