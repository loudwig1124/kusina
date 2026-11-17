import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/ui/pixel/pixel_scaffold.dart';

import '../helpers/assertions.dart';
import '../helpers/fixture_harness.dart';

/// The reference device is 360 x 640 dp at DPR 3 (`docs/07` §1.2). These tests
/// render the demo path on that surface so a layout that only fits a tall
/// window fails here; Flutter turns any overflow into a test failure.
void main() {
  testWidgets('Cook now fits 360 x 640', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, height: 640);

    expect(find.text('COOK NOW'), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    await tester.drag(find.text('Chicken Adobo'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('Crispy Pork Belly'), findsOneWidget);
    expectNoNumericInputs(tester);
  });

  testWidgets('Recipe detail fits 360 x 640 and keeps the action pinned', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/recipes/crispy-pork-belly',
      height: 640,
    );

    expect(find.text('CHOOSE PAN-FRY OR AIR-FRY'), findsOneWidget);
    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();
    expect(find.text('START COOKING'), findsOneWidget);

    await tester.drag(find.byType(PixelPage), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('START COOKING'), findsOneWidget);
  });

  testWidgets('Inventory fits 360 x 640', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/stock',
      height: 640,
    );

    expect(find.text('INVENTORY'), findsOneWidget);
    expect(find.text('Chicken thighs (Hita ng manok)'), findsOneWidget);
    expectNoNumericInputs(tester);
  });

  testWidgets('Settings fits 360 x 640', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/settings',
      height: 640,
    );

    expect(find.text('KITCHEN NAME'), findsOneWidget);
    expect(find.text('KITCHEN NAME'), findsOneWidget);
    expectNoNumericInputs(tester);
  });

  testWidgets('the guide shell fits 360 x 640', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation:
          '/guide/preview?slug=chicken-adobo&missing=ingredient:bay_leaf',
      height: 640,
    );

    expect(find.text('STEP 1 OF 7'), findsOneWidget);
  });
}
