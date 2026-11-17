import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/features/guide/guide_screen.dart';
import 'package:kusina/features/recipes/cook_now_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../../helpers/fixture_harness.dart';
import 'guide_test_helpers.dart';

void main() {
  testWidgets('Reset is blocked while a cook is in progress', (tester) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);

    // Leave the guide without abandoning: the session stays in progress.
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'LEAVE FOR NOW'));
    await tester.pumpAndSettle();
    expect(find.byType(CookNowScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('appbar-settings')));
    await tester.pumpAndSettle();

    final blocked = tester.widget<PixelButton>(
      find.widgetWithText(PixelButton, 'FINISH OR ABANDON THE COOK FIRST'),
    );
    expect(blocked.onPressed, isNull);
    expect(find.text('RESET DEMO DATA'), findsNothing);
  });

  testWidgets('abandoning the cook re-enables Reset', (tester) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);

    // Leave, come back through the recipe (the active session resumes), abandon.
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'LEAVE FOR NOW'));
    await tester.pumpAndSettle();

    // The resume card also names the dish; the card in the list is last.
    await tester.tap(find.text('Chicken Adobo').last);
    await tester.pumpAndSettle();
    // With a cook in progress the detail offers Resume, not a fresh start.
    expect(find.textContaining('A cook is in progress'), findsOneWidget);
    await tester.tap(find.widgetWithText(PixelButton, 'RESUME COOK'));
    await tester.pumpAndSettle();
    expect(find.byType(GuideScreen), findsOneWidget);
    expect(find.text('STEP 1 OF 7'), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'ABANDON COOK'));
    await tester.pumpAndSettle();
    expect(find.byType(CookNowScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('appbar-settings')));
    await tester.pumpAndSettle();
    final enabled = tester.widget<PixelButton>(
      find.widgetWithText(PixelButton, 'RESET DEMO DATA'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('a completed cook re-enables Reset', (tester) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    expect(find.byType(CookNowScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('appbar-settings')));
    await tester.pumpAndSettle();

    final enabled = tester.widget<PixelButton>(
      find.widgetWithText(PixelButton, 'RESET DEMO DATA'),
    );
    expect(enabled.onPressed, isNotNull);
  });
}
