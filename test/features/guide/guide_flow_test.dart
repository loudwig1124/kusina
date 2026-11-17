import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/features/guide/guide_screen.dart';
import 'package:kusina/features/recipes/cook_now_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';
import 'package:kusina/ui/pixel/pixel_method_control.dart';

import '../../helpers/fixture_harness.dart';
import 'guide_test_helpers.dart';

void main() {
  testWidgets('the full Adobo flow runs step 1 to 7 with taps only', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);

    expect(find.byType(GuideScreen), findsOneWidget);
    expect(find.text('STEP 1 OF 7'), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('STARTED ANYWAY'), findsOneWidget);
    expect(
      find.textContaining('ingredient:bay_leaf'),
      findsOneWidget,
      reason: 'the frozen missing list is shown',
    );
    // Nothing starts automatically: the first step is still showing.
    expect(find.widgetWithText(PixelButton, 'CONTINUE'), findsOneWidget);

    for (var step = 2; step <= 7; step++) {
      await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
      await tester.pumpAndSettle();
      expect(find.text('STEP $step OF 7'), findsOneWidget);
      expect(find.byType(GuideScreen), findsOneWidget);
    }
    expect(find.widgetWithText(PixelButton, 'FINISH'), findsOneWidget);

    await tester.tap(find.widgetWithText(PixelButton, 'FINISH'));
    await tester.pumpAndSettle();

    expect(find.text('USAGE REVIEW'), findsOneWidget);
    expect(find.text('What did you use?'), findsOneWidget);
    // One row per ingredient line, required and optional.
    expect(
      find.byKey(const ValueKey('review-line-chicken_thighs')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('review-line-bay_leaf')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-line-sugar')), findsOneWidget);
  });

  testWidgets('confirming the review returns to Cook Now and writes stock', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);

    await confirmReview(tester);

    expect(find.byType(CookNowScreen), findsOneWidget);
    expect(
      await harness.repositories.stock.getStatus('chicken_thighs'),
      StockStatus.low,
    );
    expect(
      await harness.repositories.stock.getStatus('bay_leaf'),
      StockStatus.out,
    );
    final events = await harness.repositories.stock.listEvents();
    expect(
      events.where((event) => event.cookingSessionId != null),
      hasLength(4),
      reason: 'four required have lines were used',
    );
  });

  testWidgets('Inventory reflects the usage review transitions', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    // Stock tab: the required "have" lines became Low, the untouched stay put.
    await tester.tap(find.text('STOCK'));
    await tester.pumpAndSettle();

    PixelStatusChip chipFor(String code, String status) =>
        tester.widget<PixelStatusChip>(
          find.byKey(ValueKey<String>('stock-chip-$code-$status')),
        );

    expect(chipFor('chicken_thighs', 'low').selected, isTrue);
    expect(chipFor('garlic', 'low').selected, isTrue);
    expect(chipFor('bay_leaf', 'out').selected, isTrue);
    expect(chipFor('sugar', 'have').selected, isTrue);
  });

  testWidgets('a confirmed cook leaves no guide controls on Cook Now', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    expect(find.byType(PixelMethodControl), findsNothing);
    // The session is terminal: Settings reset is available again.
    await tester.tap(find.byKey(const ValueKey<String>('appbar-settings')));
    await tester.pumpAndSettle();
    final reset = tester.widget<PixelButton>(
      find.widgetWithText(PixelButton, 'RESET DEMO DATA'),
    );
    expect(reset.onPressed, isNotNull);
  });
}
