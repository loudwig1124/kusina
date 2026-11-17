import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';
import 'package:kusina/ui/pixel/pixel_method_control.dart';

import '../../helpers/fixture_harness.dart';

Future<void> openBellyDetail(
  WidgetTester tester,
  FixtureHarness harness,
) async {
  await pumpKusinaApp(tester, harness, height: 2400);
  await tester.tap(find.text('Crispy Pork Belly'));
  await tester.pumpAndSettle();
}

PixelMethodControl methodControl(WidgetTester tester) =>
    tester.widget<PixelMethodControl>(find.byType(PixelMethodControl));

void main() {
  testWidgets('Cook Now exposes exactly the three shipped dishes', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('Sinangag'), findsOneWidget);
    expect(find.text('Crispy Pork Belly'), findsOneWidget);
    // Demo kitchen badges: Adobo blocked on the bay leaf, the other two ready.
    expect(find.text('Missing'), findsOneWidget);
    expect(find.text('Ready'), findsNWidgets(2));
    expect(find.textContaining('4 dishes'), findsNothing);
    expect(find.text("Maria's Kitchen | 3 dishes"), findsOneWidget);
  });

  testWidgets('every dish starts from Cook Now', (tester) async {
    // Chicken Adobo (guide anyway: demo kitchen is out of bay leaf).
    var harness = await createHarness();
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
    expect(find.text('STEP 1 OF 7'), findsOneWidget);

    // Sinangag (ready, single method).
    harness = await createHarness();
    await pumpKusinaApp(tester, harness, height: 2400);
    await tester.tap(find.text('Sinangag'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 1 OF 5'), findsOneWidget);
    expect(find.text('Single method'), findsOneWidget);
  });

  testWidgets('the method gating matrix follows the owned appliances', (
    tester,
  ) async {
    // Both owned: both methods ready.
    var harness = await createHarness();
    await openBellyDetail(tester, harness);
    expect(methodControl(tester).options[0].availability, isNotNull);
    expect(methodControl(tester).options[0].label, 'Pan-fry');
    expect(methodControl(tester).options[1].label, 'Air-fry');
    expect(
      methodControl(tester).options
          .map((option) => option.availability)
          .toList(),
      <Object>[AvailabilityState.ready, AvailabilityState.ready],
    );

    // Stovetop only: Pan-fry ready, Air-fry missing the air fryer.
    harness = await createHarness(ownedEquipment: <String>{'stovetop'});
    await openBellyDetail(tester, harness);
    expect(
      methodControl(tester).options
          .map((option) => option.availability)
          .toList(),
      <Object>[AvailabilityState.ready, AvailabilityState.blocked],
    );
    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();
    expect(find.text('Air Fryer is missing.'), findsOneWidget);
    expect(find.text('equipment:air_fryer'), findsNothing);
    expect(find.text('GUIDE ME ANYWAY'), findsOneWidget);

    // Air fryer only: neither method can reach the stovetop.
    harness = await createHarness(ownedEquipment: <String>{'air_fryer'});
    await openBellyDetail(tester, harness);
    expect(
      methodControl(tester).options
          .map((option) => option.availability)
          .toList(),
      <Object>[AvailabilityState.blocked, AvailabilityState.blocked],
    );
    await tester.tap(find.text('Pan-fry'));
    await tester.pumpAndSettle();
    expect(find.text('Stovetop is missing.'), findsOneWidget);
  });

  testWidgets('the picker changes the pinned path for each method', (
    tester,
  ) async {
    final harness = await createHarness(); // owns stovetop + air fryer
    await openBellyDetail(tester, harness);

    await tester.tap(find.text('Pan-fry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    expect(find.text('Pan-fry method'), findsOneWidget);
    for (var step = 1; step < 5; step++) {
      await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
      await tester.pumpAndSettle();
    }
    // The sear variant, not the air-fry canonical step.
    expect(find.textContaining('skin-side down'), findsOneWidget);
    expect(find.textContaining('air-fry at 200'), findsNothing);
  });

  testWidgets('air-fry shows the air-fry step and the air fryer requirement', (
    tester,
  ) async {
    final harness = await createHarness(ownedEquipment: <String>{'stovetop'});
    await openBellyDetail(tester, harness);

    // Guide anyway is the only path when the air fryer is missing.
    await tester.tap(find.text('Air-fry'));
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

    expect(find.text('Air-fry method'), findsOneWidget);
    expect(find.textContaining('equipment:air_fryer'), findsOneWidget);
    for (var step = 1; step < 5; step++) {
      await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('air-fry at 200'), findsOneWidget);
    expect(find.textContaining('skin-side down'), findsNothing);
  });

  testWidgets('a cook in progress locks the picker and offers Resume', (
    tester,
  ) async {
    final harness = await createHarness();
    await openBellyDetail(tester, harness);
    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    // Leave the guide without abandoning, then reopen the dish.
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'LEAVE FOR NOW'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crispy Pork Belly').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('A cook is in progress'), findsOneWidget);
    expect(
      methodControl(tester).options.every((option) => option.isDisabled),
      isTrue,
    );
    expect(find.widgetWithText(PixelButton, 'RESUME COOK'), findsOneWidget);
    expect(find.widgetWithText(PixelButton, 'START COOKING'), findsNothing);

    await tester.tap(find.widgetWithText(PixelButton, 'RESUME COOK'));
    await tester.pumpAndSettle();
    expect(find.text('Air-fry method'), findsOneWidget);
    expect(find.text('STEP 1 OF 6'), findsOneWidget);
  });

  testWidgets('Settings lists all five appliances with "No dishes yet"', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    expect(find.text('Stovetop'), findsOneWidget);
    expect(find.text('Oven'), findsOneWidget);
    expect(find.text('Air Fryer'), findsOneWidget);
    expect(find.text('Grill'), findsOneWidget);
    expect(find.text('Pressure Cooker'), findsOneWidget);
    expect(find.text('No dishes yet'), findsNWidgets(3));
    expect(find.byType(PixelFilterChip), findsNWidgets(5));
  });

  test(
    'the demo kitchen statuses that gate the dishes are as seeded',
    () async {
      final harness = await createHarness();
      expect(
        await harness.repositories.stock.getStatus('bay_leaf'),
        StockStatus.out,
      );
    },
  );
}
