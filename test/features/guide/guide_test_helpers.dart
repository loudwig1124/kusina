/// Navigation helpers shared by the guide widget tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../../helpers/fixture_harness.dart';

/// Cook Now -> Chicken Adobo -> "Guide me anyway" confirm -> guided cook.
Future<void> openAdoboGuide(WidgetTester tester, FixtureHarness harness) async {
  await pumpKusinaApp(tester, harness, height: 2400);
  await tester.tap(find.text('Chicken Adobo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GUIDE ME ANYWAY'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(PixelButton, 'GUIDE ME ANYWAY'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps CONTINUE until the final step is showing.
Future<void> advanceToLastStep(WidgetTester tester, {int steps = 7}) async {
  for (var index = 1; index < steps; index++) {
    await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
    await tester.pumpAndSettle();
  }
  expect(find.widgetWithText(PixelButton, 'FINISH'), findsOneWidget);
}

/// Runs the guide to the review sentinel.
Future<void> openAdoboReview(
  WidgetTester tester,
  FixtureHarness harness,
) async {
  await openAdoboGuide(tester, harness);
  await advanceToLastStep(tester);
  await tester.tap(find.widgetWithText(PixelButton, 'FINISH'));
  await tester.pumpAndSettle();
  expect(find.text('USAGE REVIEW'), findsOneWidget);
}

/// Confirms the review and dismisses the celebration overlay.
Future<void> confirmReview(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(PixelButton, 'CONFIRM'));
  await tester.pumpAndSettle();
  expect(find.text('COOK COMPLETE'), findsOneWidget);
  await tester.tap(find.widgetWithText(PixelButton, 'BACK TO COOK NOW'));
  await tester.pumpAndSettle();
}
