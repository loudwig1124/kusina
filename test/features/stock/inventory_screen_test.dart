import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/features/stock/inventory_screen.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';

import '../../helpers/assertions.dart';
import '../../helpers/fixture_harness.dart';

void main() {
  testWidgets('Inventory lists all 15 ingredients with a 2 x 2 chip grid', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(find.text('INVENTORY'), findsOneWidget);
    expect(find.text('15 ITEMS'), findsOneWidget);
    expect(find.text('15 OF 15'), findsOneWidget);
    expect(find.text('Chicken thighs (Hita ng manok)'), findsOneWidget);
    expect(find.text('Bay leaf (Laurel)'), findsOneWidget);

    // Four chips per row, fifteen rows.
    expect(find.byType(PixelStatusChip), findsNWidgets(60));
    expectNoNumericInputs(tester);
  });

  testWidgets('one tap writes one stock event and toasts', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('stock-chip-garlic-low')),
    );
    await tester.pumpAndSettle();

    expect(
      await harness.repositories.stock.getStatus('garlic'),
      StockStatus.low,
    );
    expect(find.text('Saved. No numbers to type.'), findsOneWidget);
    final events = await harness.repositories.stock.listEvents(
      ingredientCode: 'garlic',
    );
    expect(events, hasLength(1));
    expect(events.single.reason, StockReason.usedSome);
  });

  testWidgets('tapping the current status writes nothing', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    // Salt is already "have" in the demo kitchen.
    await tester.tap(
      find.byKey(const ValueKey<String>('stock-chip-salt-have')),
    );
    await tester.pumpAndSettle();

    expect(await harness.repositories.stock.listEvents(), isEmpty);
    expect(find.text('Saved. No numbers to type.'), findsNothing);
  });

  testWidgets('search narrows the list without any amount input', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    await tester.enterText(find.byType(TextField), 'bay');
    await tester.pumpAndSettle();

    expect(find.text('1 OF 15'), findsOneWidget);
    expect(find.text('Bay leaf (Laurel)'), findsOneWidget);
    expect(find.text('Garlic (Bawang)'), findsNothing);
    expectNoNumericInputs(tester);
  });

  testWidgets('category chips filter the list', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    await tester.tap(find.text('Meat'));
    await tester.pumpAndSettle();

    expect(find.text('2 OF 15'), findsOneWidget);
    expect(find.text('Chicken thighs (Hita ng manok)'), findsOneWidget);
    expect(find.text('Pork belly (Liempo)'), findsOneWidget);
    expect(find.text('Garlic (Bawang)'), findsNothing);
  });

  testWidgets('an empty search shows the empty copy', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No ingredient matches.'), findsOneWidget);
  });

  testWidgets('each chip is at least 48 dp tall', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 3200,
    );

    expectMinimumTapTarget(
      tester,
      find.byKey(const ValueKey<String>('stock-chip-garlic-have')),
    );
  });
}
