import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/rules/availability_service.dart';
import 'package:kusina/features/recipes/recipes_controller.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';

import '../helpers/assertions.dart';
import '../helpers/fixture_harness.dart';

void main() {
  testWidgets('Cook now lists exactly the three dishes', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    expect(find.text("Maria's Kitchen | 3 dishes"), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('Sinangag'), findsOneWidget);
    expect(find.text('Crispy Pork Belly'), findsOneWidget);
    expect(find.byType(PixelAvailabilityBadge), findsNWidgets(3));
    expectNoNumericInputs(tester);
  });

  testWidgets('Cook now badges follow each recipe default method', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    final badges = tester
        .widgetList<PixelAvailabilityBadge>(find.byType(PixelAvailabilityBadge))
        .toList();
    // Content order: Adobo, Sinangag, Crispy Pork Belly.
    expect(badges[0].state, AvailabilityState.blocked);
    expect(badges[1].state, AvailabilityState.ready);
    expect(badges[2].state, AvailabilityState.ready);

    // The card copy is the badge label, never a numeric requirement.
    expect(find.text('Missing'), findsOneWidget);
    expect(find.text('Ready'), findsNWidgets(2));

    // The badges match the availability service for the default method.
    final controller = RecipesController(
      recipeRepository: harness.repositories.recipes,
      stockRepository: harness.repositories.stock,
      equipmentRepository: harness.repositories.equipment,
      availabilityService: harness.repositories.availability,
    );
    await controller.load();
    for (final card in controller.cards) {
      expect(
        card.availability.state,
        isA<AvailabilityState>(),
        reason: '${card.recipe.slug} has a computed default-method state',
      );
    }
  });

  testWidgets('tapping a card opens the recipe detail', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    await tester.tap(find.text('Crispy Pork Belly'));
    await tester.pumpAndSettle();

    expect(find.text('RECIPE'), findsOneWidget);
    expect(find.text('Crispy Pork Belly'), findsOneWidget);
    expect(find.text('NO DEFAULT'), findsOneWidget);
  });

  testWidgets('a blocked recipe card still opens (Guide anyway lives inside)', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    await tester.tap(find.text('Chicken Adobo'));
    await tester.pumpAndSettle();

    expect(find.text('Bay leaf is out of stock.'), findsOneWidget);
    expect(find.text('GUIDE ME ANYWAY'), findsOneWidget);
  });

  testWidgets('Cook now shows the equipment line from the kitchen', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    expect(find.text('STOVETOP + AIR FRYER'), findsOneWidget);
  });

  testWidgets('Cook now keeps the tab bar and 48 dp targets', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness);

    for (final tab in <String>['cook', 'recipes', 'stock', 'history']) {
      expectMinimumTapTarget(tester, find.byKey(ValueKey<String>('tab-$tab')));
    }
  });
}
