import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/screens/onboarding_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('OnboardingScreen', () {
    testWidgets('shows app name', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('Burrow'), findsOneWidget);
    });

    testWidgets('shows marmot emoji', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('🦫'), findsOneWidget);
    });

    testWidgets('shows tagline', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('Your keys, your identity.'), findsOneWidget);
    });

    testWidgets('shows privacy message', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('No phone number. No email. No tracking.'), findsOneWidget);
    });

    testWidgets('has Create New Identity button', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('Create New Identity'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('has Import Existing Key button', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('Import Existing Key'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('shows protocol footer', (tester) async {
      await tester.pumpWidget(wrap(const OnboardingScreen()));
      expect(find.text('Marmot Protocol • MLS + Nostr'), findsOneWidget);
    });
  });
}
