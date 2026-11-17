import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../../helpers/fixture_harness.dart';
import 'guide_test_helpers.dart';

void main() {
  testWidgets('no card without an active session, card after leaving a cook', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    expect(find.text('COOK IN PROGRESS'), findsNothing);
    expect(find.widgetWithText(PixelButton, 'RESUME'), findsNothing);

    await openAdoboGuide(tester, harness);
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'LEAVE FOR NOW'));
    await tester.pumpAndSettle();

    expect(find.text('COOK IN PROGRESS'), findsOneWidget);
    expect(find.textContaining('Step 1 of 7'), findsOneWidget);
    expect(
      find.textContaining('Started anyway: ingredient:bay_leaf'),
      findsOneWidget,
    );

    // Resume opens the guide where the cook left off.
    await tester.tap(find.widgetWithText(PixelButton, 'RESUME'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 1 OF 7'), findsOneWidget);
    expect(find.text('Single method'), findsOneWidget);
  });

  testWidgets('Abandon on the card writes no stock events', (tester) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'LEAVE FOR NOW'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PixelButton, 'ABANDON'));
    await tester.pumpAndSettle();
    expect(find.text('ABANDON THIS COOK?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(PixelButton, 'ABANDON'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COOK IN PROGRESS'), findsNothing);
    expect(find.text('Cook abandoned. No stock changed.'), findsOneWidget);
    expect(await harness.repositories.stock.listEvents(), isEmpty);
  });

  testWidgets('the card is gone once the cook is completed', (tester) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    expect(find.text('COOK IN PROGRESS'), findsNothing);
  });
}
