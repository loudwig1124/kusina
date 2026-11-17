import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../../helpers/fixture_harness.dart';
import 'guide_test_helpers.dart';

void main() {
  testWidgets('review offers exactly three choices per line', (tester) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);

    for (final choice in <String>['didntUse', 'usedIt', 'usedItUp']) {
      expect(
        find.byKey(ValueKey<String>('review-choice-chicken_thighs-$choice')),
        findsOneWidget,
        reason: '$choice must exist on every line',
      );
      expect(
        find.byKey(ValueKey<String>('review-choice-bay_leaf-$choice')),
        findsOneWidget,
      );
    }
    // Optional lines are listed too, with the same three choices.
    expect(find.byKey(const ValueKey('review-line-sugar')), findsOneWidget);
  });

  testWidgets('Used it is disabled on an out line and enabled after restock', (
    tester,
  ) async {
    final harness = await createHarness();
    final semantics = tester.ensureSemantics();
    await openAdoboReview(tester, harness);

    final bayLeafUsedIt = find.byKey(
      const ValueKey<String>('review-choice-bay_leaf-usedIt'),
    );
    expect(
      tester
          .getSemantics(bayLeafUsedIt)
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
      reason: 'out + Used it is disabled, not a silent no-op',
    );

    // "I have it" restocks the line, which makes the usage legal.
    await tester.tap(find.byKey(const ValueKey('review-restock-bay_leaf')));
    await tester.pumpAndSettle();
    expect(find.text('I have it ✓'), findsOneWidget);
    expect(
      tester
          .getSemantics(bayLeafUsedIt)
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('a no-op choice says why it writes nothing', (tester) async {
    final demo = (await createHarness()).statuses;
    final lowVinegar = await createHarness(
      statuses: <String, StockStatus>{...demo, 'vinegar': StockStatus.low},
    );
    await openAdoboReview(tester, lowVinegar);

    // Vinegar is required and low: the default "Used it" is a no-op and says so.
    expect(
      find.text('Already low: this choice writes nothing.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(PixelButton, 'CONFIRM'));
    await tester.pumpAndSettle();
    expect(find.text('COOK COMPLETE'), findsOneWidget);
    expect(
      await lowVinegar.repositories.stock.getStatus('vinegar'),
      StockStatus.low,
    );
    expect(
      await lowVinegar.repositories.stock.listEvents(ingredientCode: 'vinegar'),
      isEmpty,
    );
  });

  testWidgets('restock + Used it chains two events on confirm', (tester) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);

    await tester.tap(find.byKey(const ValueKey('review-restock-bay_leaf')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('review-choice-bay_leaf-usedIt')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'CONFIRM'));
    await tester.pumpAndSettle();

    expect(find.text('COOK COMPLETE'), findsOneWidget);
    expect(find.textContaining('used'), findsWidgets);
    expect(
      await harness.repositories.stock.getStatus('bay_leaf'),
      StockStatus.low,
    );
    final bayLeafEvents = await harness.repositories.stock.listEvents(
      ingredientCode: 'bay_leaf',
    );
    expect(bayLeafEvents, hasLength(2));
    // Both events share the fixed clock instant, so assert the facts, not the
    // list order.
    expect(bayLeafEvents.map((event) => event.reason).toSet(), <StockReason>{
      StockReason.restock,
      StockReason.usedSome,
    });
    final restock = bayLeafEvents.firstWhere(
      (event) => event.reason == StockReason.restock,
    );
    expect(restock.from, StockStatus.out);
    expect(restock.to, StockStatus.have);
    expect(restock.cookingSessionId, isNull);
    final usage = bayLeafEvents.firstWhere(
      (event) => event.reason == StockReason.usedSome,
    );
    expect(usage.from, StockStatus.have);
    expect(usage.to, StockStatus.low);
    expect(usage.cookingSessionId, isNotNull);

    await tester.tap(find.widgetWithText(PixelButton, 'BACK TO COOK NOW'));
    await tester.pumpAndSettle();
    expect(find.text('COOK NOW'), findsOneWidget);
  });

  testWidgets('the default confirm leaves unknown and out lines untouched', (
    tester,
  ) async {
    // Calamansi is optional-unknown and banana ketchup optional-unknown in the
    // demo kitchen; neither default writes anything.
    final harness = await createHarness();
    await openAdoboReview(tester, harness);

    await confirmReview(tester);

    expect(
      await harness.repositories.stock.getStatus('spring_onion'),
      StockStatus.low,
    );
    expect(
      await harness.repositories.stock.getStatus('bay_leaf'),
      StockStatus.out,
    );
    final allEvents = await harness.repositories.stock.listEvents();
    expect(
      allEvents,
      hasLength(4),
      reason: 'only the four required have lines',
    );
  });
}
