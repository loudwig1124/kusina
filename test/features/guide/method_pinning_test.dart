import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_method_control.dart';

import '../../helpers/fixture_harness.dart';

void main() {
  testWidgets('Air-fry is frozen into the guide and cannot be changed', (
    tester,
  ) async {
    final harness = await createHarness(); // owns stovetop + air fryer
    await pumpKusinaApp(tester, harness, height: 2400);

    await tester.tap(find.text('Crispy Pork Belly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF 6'), findsOneWidget);
    expect(find.text('Air-fry method'), findsOneWidget);
    // No control exists in the guide to change the method mid-cook.
    expect(find.byType(PixelMethodControl), findsNothing);
    expect(find.text('Pan-fry'), findsNothing);

    // Walk to the method-dependent crisp step and read the air-fry copy.
    for (var index = 1; index < 5; index++) {
      await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
      await tester.pumpAndSettle();
    }
    expect(find.text('STEP 5 OF 6'), findsOneWidget);
    expect(find.textContaining('air-fry at 200'), findsOneWidget);
    expect(find.textContaining('skin-side down'), findsNothing);
    expect(find.text('Air-fry method'), findsOneWidget);
  });

  testWidgets('a Pan-fry pick renders the pan-fry variant copy', (
    tester,
  ) async {
    final harness = await createHarness(ownedEquipment: <String>{'stovetop'});
    await pumpKusinaApp(tester, harness, height: 2400);

    await tester.tap(find.text('Crispy Pork Belly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pan-fry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    expect(find.text('Pan-fry method'), findsOneWidget);
    for (var index = 1; index < 5; index++) {
      await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
      await tester.pumpAndSettle();
    }
    expect(find.text('STEP 5 OF 6'), findsOneWidget);
    expect(find.textContaining('skin-side down'), findsOneWidget);
    expect(find.textContaining('air-fry at 200'), findsNothing);
  });

  testWidgets('a blocked pick starts only through Guide anyway and shows the '
      'frozen missing list', (tester) async {
    final harness = await createHarness(ownedEquipment: <String>{'stovetop'});
    await pumpKusinaApp(tester, harness, height: 2400);

    await tester.tap(find.text('Crispy Pork Belly'));
    await tester.pumpAndSettle();
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

    expect(find.text('STARTED ANYWAY'), findsOneWidget);
    expect(find.textContaining('equipment:air_fryer'), findsOneWidget);
    expect(find.text('Air-fry method'), findsOneWidget);
  });
}
