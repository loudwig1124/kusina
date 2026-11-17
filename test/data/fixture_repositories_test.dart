import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/di.dart';
import 'package:kusina/domain/models/stock.dart';

import '../helpers/fixture_harness.dart';

void main() {
  test('recipe repository lists in sort order and looks up by slug', () async {
    final harness = await createHarness();
    final recipes = harness.repositories.recipes;

    final all = await recipes.listRecipes();
    expect(all.map((recipe) => recipe.slug).toList(), <String>[
      'chicken-adobo',
      'sinangag',
      'crispy-pork-belly',
    ]);
    expect(await recipes.findBySlug('sinangag'), isNotNull);
    expect(await recipes.findBySlug('chicken-adobo'), isNotNull);
    expect(await recipes.findBySlug('nope'), isNull);
  });

  test('stock repository starts from the demo tri-state', () async {
    final harness = await createHarness();
    final stock = harness.repositories.stock;

    final ingredients = await stock.listIngredients();
    expect(ingredients, hasLength(15));
    expect(await stock.getStatus('bay_leaf'), StockStatus.out);
    expect(await stock.getStatus('spring_onion'), StockStatus.low);
    expect(await stock.getStatus('salt'), StockStatus.have);

    final statuses = await stock.getStatuses(<String>['bay_leaf', 'salt']);
    expect(statuses, <String, StockStatus>{
      'bay_leaf': StockStatus.out,
      'salt': StockStatus.have,
    });
  });

  test('setStatus writes one legal event and updates the status', () async {
    final harness = await createHarness();
    final stock = harness.repositories.stock;

    final event = await stock.setStatus(
      ingredientCode: 'bay_leaf',
      to: StockStatus.have,
      reason: StockReason.restock,
    );

    expect(event, isNotNull);
    expect(event!.from, StockStatus.out);
    expect(event.to, StockStatus.have);
    expect(event.reason, StockReason.restock);
    expect(await stock.getStatus('bay_leaf'), StockStatus.have);

    final events = await stock.listEvents(ingredientCode: 'bay_leaf');
    expect(events, hasLength(1));
  });

  test('a no-op writes nothing', () async {
    final harness = await createHarness();
    final stock = harness.repositories.stock;

    final event = await stock.setStatus(
      ingredientCode: 'salt',
      to: StockStatus.have,
      reason: StockReason.restock,
    );

    expect(event, isNull);
    expect(await stock.listEvents(), isEmpty);
  });

  test('an illegal reason is rejected', () async {
    final harness = await createHarness();
    final stock = harness.repositories.stock;

    expect(
      () => stock.setStatus(
        ingredientCode: 'salt',
        to: StockStatus.low,
        reason: StockReason.restock,
      ),
      throwsArgumentError,
    );
  });

  test('recordEvent rejects a stale from status', () async {
    final harness = await createHarness();
    final stock = harness.repositories.stock;

    expect(
      () => stock.recordEvent(
        const StockEventDraft(
          ingredientCode: 'salt',
          from: StockStatus.out,
          to: StockStatus.have,
          reason: StockReason.restock,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'equipment repository owns exactly the demo set and can replace it',
    () async {
      final harness = await createHarness();
      final equipment = harness.repositories.equipment;

      expect(await equipment.catalog(), hasLength(5));
      expect(await equipment.ownedIds(), <String>{'stovetop', 'air_fryer'});

      await equipment.setOwned(<String>{'stovetop'});
      expect(await equipment.ownedIds(), <String>{'stovetop'});
      expect(
        () => equipment.setOwned(<String>{'stovetop', 'microwave'}),
        throwsArgumentError,
      );
    },
  );

  test('kitchen repository renames the one profile', () async {
    final harness = await createHarness();
    final kitchen = harness.repositories.kitchen;

    final initial = await kitchen.get();
    expect(initial.name, "Maria's Kitchen");

    final renamed = await kitchen.rename('  Lola Rosa  ');
    expect(renamed.name, 'Lola Rosa');
    expect(() => kitchen.rename('   '), throwsArgumentError);
  });

  test('resetDemoData restores stock, equipment and the profile', () async {
    final harness = await createHarness();
    final stock = harness.repositories.stock;
    final equipment = harness.repositories.equipment;
    final kitchen = harness.repositories.kitchen;

    await stock.setStatus(
      ingredientCode: 'bay_leaf',
      to: StockStatus.have,
      reason: StockReason.restock,
    );
    await equipment.setOwned(<String>{});
    await kitchen.rename('Test Kitchen');

    await harness.repositories.resetDemoData();

    expect(await stock.getStatus('bay_leaf'), StockStatus.out);
    expect(await equipment.ownedIds(), <String>{'stovetop', 'air_fryer'});
    expect((await kitchen.get()).name, "Maria's Kitchen");
    expect(await stock.listEvents(), isEmpty);
  });

  test('the seed loader reports the content seed version', () async {
    final harness = await createHarness();
    expect(await harness.repositories.seedLoader.seedVersion(), 1);
    expect(await harness.repositories.seedLoader.schemaVersion(), 0);
  });

  testWidgets('the composition root builds the fixture set from the assets', (
    tester,
  ) async {
    // The real path main() takes: bundled assets -> FixtureBundle -> ports.
    final repositories = await Repositories.fixtures();

    expect(repositories.kitchenConfigured, isTrue);
    expect(
      (await repositories.recipes.listRecipes())
          .map((recipe) => recipe.slug)
          .toList(),
      <String>['chicken-adobo', 'sinangag', 'crispy-pork-belly'],
    );
    expect(await repositories.equipment.ownedIds(), <String>{
      'stovetop',
      'air_fryer',
    });
    expect(await repositories.stock.getStatus('bay_leaf'), StockStatus.out);
    expect((await repositories.kitchen.get()).name, "Maria's Kitchen");
    expect((await repositories.stock.listIngredients()).length, 15);
  });
}
