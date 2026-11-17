import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/features/recipes/cook_now_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_panel.dart';

import '../../helpers/fixture_harness.dart';
import '../guide/guide_test_helpers.dart';

void main() {
  testWidgets('completion plays the dish-stamp celebration once', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);

    await tester.tap(find.widgetWithText(PixelButton, 'CONFIRM'));
    await tester.pumpAndSettle();

    // The overlay: dish stamp, full progress, one shared frame.
    expect(find.text('COOK COMPLETE'), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.textContaining('4 used'), findsOneWidget);
    expect(find.textContaining('not used'), findsOneWidget);
    expect(find.text('Saved to History.'), findsOneWidget);
    expect(find.bySemanticsLabel('Chicken Adobo stamp'), findsOneWidget);
    expect(find.byType(PixelPanel), findsWidgets);

    await tester.tap(find.widgetWithText(PixelButton, 'BACK TO COOK NOW'));
    await tester.pumpAndSettle();
    expect(find.byType(CookNowScreen), findsOneWidget);
    expect(find.text('COOK COMPLETE'), findsNothing);

    // The cook is terminal: History shows it, and no celebration can re-fire.
    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('COOK COMPLETE'), findsNothing);
  });

  testWidgets('a second confirm on the same cook does not celebrate again', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    // Reloading the review for a completed session shows the guard copy, not
    // another celebration.
    await tester.tap(find.text('Chicken Adobo').last);
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

    // The session completed, so a fresh start is possible; no stale overlay.
    expect(find.text('COOK COMPLETE'), findsNothing);
    expect(find.text('STEP 1 OF 7'), findsOneWidget);
  });
}
