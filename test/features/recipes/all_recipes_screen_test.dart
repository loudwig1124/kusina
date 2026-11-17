import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';
import 'package:kusina/features/recipes/all_recipes_screen.dart';
import 'package:kusina/features/recipes/recipe_detail_screen.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';

import '../../helpers/assertions.dart';
import '../../helpers/fixture_harness.dart';

void main() {
  testWidgets('All recipes lists the three dishes with equipment and badges', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/recipes');

    expect(find.byType(AllRecipesScreen), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('Sinangag'), findsOneWidget);
    expect(find.text('Crispy Pork Belly'), findsOneWidget);
    expect(find.byType(PixelAvailabilityBadge), findsNWidgets(3));
    // The method dish names its two methods instead of a single appliance.
    expect(find.text('Pan-fry / Air-fry'), findsOneWidget);
    expect(find.text('Stovetop'), findsNWidgets(2));
    expectNoNumericInputs(tester);
  });

  testWidgets('filtering by state narrows the list and can empty it', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/recipes');

    await tester.tap(find.widgetWithText(PixelFilterChip, 'Missing'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('Sinangag'), findsNothing);

    await tester.tap(find.widgetWithText(PixelFilterChip, 'Ready'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Adobo'), findsNothing);
    expect(find.text('Crispy Pork Belly'), findsOneWidget);
  });

  testWidgets('a filter with no match shows the empty copy', (tester) async {
    // Everything on hand: nothing is Missing, so that filter is empty.
    final harness = await createHarness();
    final allHave = <String, StockStatus>{
      for (final code in harness.statuses.keys) code: StockStatus.have,
    };
    await createHarness(statuses: allHave);
    await pumpKusinaApp(
      tester,
      await createHarness(statuses: allHave),
      initialLocation: '/recipes',
    );

    await tester.tap(find.widgetWithText(PixelFilterChip, 'Missing'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches. Clear filter.'), findsOneWidget);
    expect(find.byType(PixelAvailabilityBadge), findsNothing);
  });

  testWidgets('a row opens the recipe detail', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/recipes');

    await tester.tap(find.text('Chicken Adobo'));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(find.text('Bay leaf is out of stock.'), findsOneWidget);
  });

  testWidgets('the badges are the three locked labels', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/recipes');

    final states = tester
        .widgetList<PixelAvailabilityBadge>(find.byType(PixelAvailabilityBadge))
        .map((badge) => badge.state)
        .toList();
    expect(states, <AvailabilityState>[
      AvailabilityState.blocked,
      AvailabilityState.ready,
      AvailabilityState.ready,
    ]);
  });
}
