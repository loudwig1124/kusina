import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/features/recipes/cook_now_screen.dart';
import 'package:kusina/features/settings/settings_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../helpers/assertions.dart';
import '../helpers/fixture_harness.dart';

void main() {
  testWidgets('Settings shows name, equipment, note and reset', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('KITCHEN NAME'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('This stays on this phone.'), findsOneWidget);
    expect(find.text('RESET DEMO DATA'), findsOneWidget);
    expect(find.text('Kusina 1.0.0 · SQLite'), findsOneWidget);
    expectNoNumericInputs(tester);
  });

  testWidgets('renaming the kitchen persists and shows on Cook now', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    await tester.enterText(find.byType(TextField).first, 'Lola Rosa');
    await tester.tap(find.widgetWithText(PixelButton, 'SAVE NAME'));
    await tester.pumpAndSettle();

    expect((await harness.repositories.kitchen.get()).name, 'Lola Rosa');
    expect(find.text('Saved. This stays on this phone.'), findsOneWidget);

    // Back to the shell; Cook now greets the renamed kitchen.
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    expect(find.byType(CookNowScreen), findsOneWidget);
    expect(find.text('Lola Rosa | 3 dishes'), findsOneWidget);
  });

  testWidgets('an equipment toggle changes availability for the next read', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    final airFryerRow = find.byKey(
      const ValueKey<String>('equipment-air_fryer'),
    );
    await tester.tap(
      find.descendant(of: airFryerRow, matching: find.text('Owned')),
    );
    await tester.pumpAndSettle();

    expect(await harness.repositories.equipment.ownedIds(), <String>{
      'stovetop',
    });

    // A fresh read of the detail screen now finds the air fryer missing.
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/recipes/crispy-pork-belly',
    );
    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();
    expect(find.text('Air Fryer is missing.'), findsOneWidget);
  });

  testWidgets('Reset demo data confirms and restores the demo state', (
    tester,
  ) async {
    final harness = await createHarness();
    await harness.repositories.stock.setStatus(
      ingredientCode: 'bay_leaf',
      to: StockStatus.have,
      reason: StockReason.restock,
    );
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    await tester.tap(find.widgetWithText(PixelButton, 'RESET DEMO DATA'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('RESET DEMO DATA'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(PixelButton, 'RESET'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      await harness.repositories.stock.getStatus('bay_leaf'),
      StockStatus.out,
    );
    expect(await harness.repositories.stock.listEvents(), isEmpty);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('cancelling the reset keeps the demo untouched', (tester) async {
    final harness = await createHarness();
    await harness.repositories.stock.setStatus(
      ingredientCode: 'bay_leaf',
      to: StockStatus.have,
      reason: StockReason.restock,
    );
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    await tester.tap(find.widgetWithText(PixelButton, 'RESET DEMO DATA'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(PixelButton, 'CANCEL'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      await harness.repositories.stock.getStatus('bay_leaf'),
      StockStatus.have,
    );
  });
}
