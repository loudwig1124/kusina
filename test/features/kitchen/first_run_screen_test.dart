import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/di.dart';
import 'package:kusina/features/kitchen/first_run_screen.dart';
import 'package:kusina/features/recipes/cook_now_screen.dart';
import 'package:kusina/features/recipes/recipe_detail_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../../helpers/assertions.dart';
import '../../helpers/fixture_harness.dart';

void main() {
  testWidgets('first run shows the profile form and the privacy note', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/setup');

    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.text('KITCHEN NAME'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('This stays on this phone.'), findsOneWidget);
    expect(find.text('START COOKING'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
    expectNoNumericInputs(tester);
    // No back button on first run.
    expect(find.byKey(const ValueKey<String>('appbar-back')), findsNothing);
  });

  testWidgets('a fresh install redirects to the setup screen', (tester) async {
    final harness = await createHarness();
    final base = harness.repositories;
    final unconfigured = Repositories(
      recipes: base.recipes,
      stock: base.stock,
      equipment: base.equipment,
      kitchen: base.kitchen,
      seedLoader: base.seedLoader,
      availability: base.availability,
      kitchenConfigured: false,
    );

    await pumpKusinaAppWithRepositories(
      tester,
      unconfigured,
      initialLocation: '/',
    );

    expect(find.byType(FirstRunScreen), findsOneWidget);
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.byType(CookNowScreen), findsNothing);
  });

  testWidgets('Start cooking saves the name and lands on Cook now', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/setup');

    await tester.enterText(find.byType(TextField), 'Lola Rosa');
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    expect((await harness.repositories.kitchen.get()).name, 'Lola Rosa');
    expect(find.byType(CookNowScreen), findsOneWidget);
    expect(find.text('Lola Rosa | 3 dishes'), findsOneWidget);
  });

  testWidgets('Skip keeps the profile and lands on Cook now', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/setup');

    await tester.tap(find.widgetWithText(PixelButton, 'SKIP'));
    await tester.pumpAndSettle();

    expect(find.byType(CookNowScreen), findsOneWidget);
    expect((await harness.repositories.kitchen.get()).name, "Maria's Kitchen");
  });

  testWidgets('a fresh install can Skip out of setup (stale-flag regression)', (
    tester,
  ) async {
    final harness = await createHarness();
    final base = harness.repositories;
    final unconfigured = Repositories(
      recipes: base.recipes,
      stock: base.stock,
      equipment: base.equipment,
      kitchen: base.kitchen,
      seedLoader: base.seedLoader,
      availability: base.availability,
      kitchenConfigured: false,
    );
    await pumpKusinaAppWithRepositories(
      tester,
      unconfigured,
      initialLocation: '/setup',
    );

    await tester.tap(find.widgetWithText(PixelButton, 'SKIP'));
    await tester.pumpAndSettle();

    expect(find.byType(CookNowScreen), findsOneWidget);
    expect(find.byType(FirstRunScreen), findsNothing);
    expect(unconfigured.kitchenConfigured, isTrue);
  });

  testWidgets('a fresh install can Start cooking out of setup', (tester) async {
    final harness = await createHarness();
    final base = harness.repositories;
    final unconfigured = Repositories(
      recipes: base.recipes,
      stock: base.stock,
      equipment: base.equipment,
      kitchen: base.kitchen,
      seedLoader: base.seedLoader,
      availability: base.availability,
      kitchenConfigured: false,
    );
    await pumpKusinaAppWithRepositories(
      tester,
      unconfigured,
      initialLocation: '/setup',
    );

    await tester.enterText(find.byType(TextField), 'Lola Rosa');
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    expect(find.byType(CookNowScreen), findsOneWidget);
    expect((await harness.repositories.kitchen.get()).name, 'Lola Rosa');
    expect(unconfigured.kitchenConfigured, isTrue);
  });

  testWidgets('an empty kitchen name is refused with inline copy', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/setup');

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(PixelButton, 'START COOKING'));
    await tester.pumpAndSettle();

    expect(find.text('Give the kitchen a name to continue.'), findsOneWidget);
    expect((await harness.repositories.kitchen.get()).name, "Maria's Kitchen");
  });

  testWidgets('equipment can be unowned from first run without blocking it', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/setup');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('equipment-air_fryer')),
        matching: find.text('Owned'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'SKIP'));
    await tester.pumpAndSettle();

    expect(await harness.repositories.equipment.ownedIds(), <String>{
      'stovetop',
    });
    expect(find.byType(CookNowScreen), findsOneWidget);
  });

  testWidgets('the method dish is blocked on the detail screen, not hidden', (
    tester,
  ) async {
    final harness = await createHarness(ownedEquipment: <String>{});
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/recipes/crispy-pork-belly',
    );

    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();

    // Both appliances are missing, and waiting for a pick is not an excuse to
    // hide the dish.
    expect(find.text('2 requirements are missing.'), findsOneWidget);
    expect(find.text('2 MISSING ITEMS'), findsOneWidget);
    expect(find.text('Air Fryer is missing.'), findsOneWidget);
    expect(find.text('Stovetop is missing.'), findsOneWidget);
    expect(find.text('GUIDE ME ANYWAY'), findsOneWidget);
  });

  testWidgets('the confirm sheet names every missing requirement', (
    tester,
  ) async {
    final harness = await createHarness(ownedEquipment: <String>{});
    await pumpKusinaApp(
      tester,
      harness,
      initialLocation: '/recipes/crispy-pork-belly',
    );

    await tester.tap(find.text('Air-fry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GUIDE ME ANYWAY'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('Air Fryer is missing.'), findsWidgets);
    expect(find.textContaining('Stovetop is missing.'), findsWidgets);
  });
}
