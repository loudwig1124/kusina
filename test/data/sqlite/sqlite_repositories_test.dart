import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/data/sqlite/mappers.dart';
import 'package:kusina/domain/models/stock.dart';

import 'sqlite_harness.dart';

void main() {
  late SqliteHarness harness;

  setUp(() async {
    harness = await createSqliteHarness();
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('recipe repository', () {
    test('lists the three dishes in content order', () async {
      final recipes = await harness.repositories.recipes.listRecipes();
      expect(recipes.map((recipe) => recipe.slug).toList(), <String>[
        'chicken-adobo',
        'sinangag',
        'crispy-pork-belly',
      ]);
      expect(recipes.map((recipe) => recipe.name).toList(), <String>[
        'Chicken Adobo',
        'Sinangag',
        'Crispy Pork Belly',
      ]);
      expect(recipes.map((recipe) => recipe.sortOrder).toList(), <int>[
        1,
        2,
        3,
      ]);
      expect(recipes.map((recipe) => recipe.dishStampKey).toList(), <String>[
        'dish_chicken_adobo',
        'dish_sinangag',
        'dish_crispy_pork_belly',
      ]);
    });

    test('Chicken Adobo reloads its steps, lines and equipment', () async {
      final adobo = await harness.repositories.recipes.findBySlug(
        'chicken-adobo',
      );

      expect(adobo, isNotNull);
      expect(adobo!.steps, hasLength(7));
      expect(adobo.steps.first.stepNumber, 1);
      expect(adobo.steps.first.kind.wireCode, 'prep');
      expect(adobo.steps[1].durationSeconds, 480);
      expect(adobo.steps[1].equipmentCode, 'stovetop');
      expect(adobo.steps[4].durationSeconds, 1500);
      expect(adobo.steps.last.kind.wireCode, 'finish');
      expect(adobo.requiredEquipmentCodes, <String>['stovetop']);
      expect(adobo.hasMethodChoice, isFalse);
      expect(adobo.requiredLines, hasLength(5));
      expect(adobo.optionalLines, hasLength(3));
      final chicken = adobo.lines.first;
      expect(chicken.ingredientCode, 'chicken_thighs');
      expect(chicken.name, 'Chicken thighs');
      expect(chicken.quantityLabel, '1000 g');
      expect(chicken.preparationNote, 'Bone-in, cut into serving pieces');
    });

    test(
      'Crispy Pork Belly reloads both methods and the crisp variant',
      () async {
        final pork = await harness.repositories.recipes.findBySlug(
          'crispy-pork-belly',
        );

        expect(pork, isNotNull);
        expect(pork!.name, 'Crispy Pork Belly');
        expect(pork.steps, hasLength(6));
        expect(pork.hasMethodChoice, isTrue);
        expect(pork.methods.map((method) => method.key).toList(), <String>[
          'pan_fry',
          'air_fry',
        ]);
        expect(pork.methods.map((method) => method.label).toList(), <String>[
          'Pan-fry',
          'Air-fry',
        ]);
        expect(
          pork.methods.map((method) => method.equipmentCode).toList(),
          <String>['stovetop', 'air_fryer'],
        );
        expect(pork.canonicalMethod!.key, 'air_fry');
        expect(pork.methodFor('pan_fry')!.isCanonical, isFalse);
        expect(pork.requiredEquipmentCodes, isEmpty);

        final crisp = pork.steps[4];
        expect(crisp.variantGroup, 'cook_method');
        final airFry = crisp.resolveFor(pork.methodFor('air_fry'))!;
        expect(airFry.isVariant, isFalse);
        expect(airFry.equipmentCode, 'air_fryer');
        expect(airFry.durationSeconds, 1200);
        expect(airFry.spriteKey, 'step_cook_air_fryer');

        final panFry = crisp.resolveFor(pork.methodFor('pan_fry'))!;
        expect(panFry.isVariant, isTrue);
        expect(panFry.equipmentCode, 'stovetop');
        expect(panFry.durationSeconds, 720);
        expect(panFry.spriteKey, 'step_cook_stovetop');
        expect(panFry.variant!.priority, 10);

        expect(pork.equipmentCodesFor('pan_fry'), <String>{'stovetop'});
        expect(pork.equipmentCodesFor('air_fry'), <String>{
          'stovetop',
          'air_fryer',
        });
      },
    );

    test('an unknown slug returns null', () async {
      expect(await harness.repositories.recipes.findBySlug('nope'), isNull);
    });
  });

  group('catalog repositories', () {
    test('ingredients reload with the derived display unit', () async {
      final ingredients = await harness.repositories.stock.listIngredients();
      expect(ingredients, hasLength(15));
      final garlic = ingredients.firstWhere(
        (ingredient) => ingredient.code == 'garlic',
      );
      expect(garlic.name, 'Garlic');
      expect(garlic.category, 'produce');
      expect(garlic.displayUnit, 'clove');
      expect(garlic.defaultStatus, StockStatus.unknown);
      expect(garlic.spriteKey, 'ing_garlic');
    });

    test('equipment catalog derives shipped from recipe use', () async {
      final catalog = await harness.repositories.equipment.catalog();
      expect(catalog, hasLength(5));
      expect(catalog.map((item) => item.code).toList(), <String>[
        'stovetop',
        'oven',
        'air_fryer',
        'grill',
        'pressure_cooker',
      ]);
      final shipped = catalog
          .where((item) => item.shipped)
          .map((item) => item.code)
          .toSet();
      expect(shipped, <String>{'stovetop', 'air_fryer'});
      expect(
        catalog.firstWhere((item) => item.code == 'oven').pickerNote,
        'No dishes yet',
      );
      expect(catalog.first.spriteKey, 'eq_stovetop');
    });

    test(
      'ownership replaces the owned set and rejects unknown codes',
      () async {
        final equipment = harness.repositories.equipment;
        expect(await equipment.ownedIds(), <String>{'stovetop', 'air_fryer'});

        await equipment.setOwned(<String>{'stovetop'});
        expect(await equipment.ownedIds(), <String>{'stovetop'});

        expect(
          () => equipment.setOwned(<String>{'stovetop', 'microwave'}),
          throwsArgumentError,
        );
        expect(await equipment.ownedIds(), <String>{'stovetop'});
      },
    );

    test('the kitchen profile round-trips and renames', () async {
      final kitchen = harness.repositories.kitchen;
      final profile = await kitchen.get();
      expect(profile.name, "Maria's Kitchen");
      expect(profile.uid.length, greaterThanOrEqualTo(16));

      final renamed = await kitchen.rename('  Lola Rosa  ');
      expect(renamed.name, 'Lola Rosa');

      // A new repository over the same DB sees the write.
      final reloaded = await harness.repositories.kitchen.get();
      expect(reloaded.name, 'Lola Rosa');
      expect(() => kitchen.rename('   '), throwsArgumentError);
    });
  });

  group('stock repository', () {
    test('reads the seeded tri-state', () async {
      final stock = harness.repositories.stock;
      expect(await stock.getStatus('bay_leaf'), StockStatus.out);
      expect(await stock.getStatus('spring_onion'), StockStatus.low);
      expect(await stock.getStatus('salt'), StockStatus.have);
      expect(
        await stock.getStatuses(<String>['bay_leaf', 'salt']),
        <String, StockStatus>{
          'bay_leaf': StockStatus.out,
          'salt': StockStatus.have,
        },
      );
      // An unknown code reads as unknown, never as out.
      expect(await stock.getStatus('not_in_catalog'), StockStatus.unknown);
    });

    test(
      'a legal transition writes one event and updates the status',
      () async {
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
        expect(event.cookingSessionId, isNull);
        expect(await stock.getStatus('bay_leaf'), StockStatus.have);
        expect(
          await stock.listEvents(ingredientCode: 'bay_leaf'),
          hasLength(1),
        );
      },
    );

    test('a no-op writes nothing', () async {
      final stock = harness.repositories.stock;
      expect(
        await stock.setStatus(
          ingredientCode: 'salt',
          to: StockStatus.have,
          reason: StockReason.restock,
        ),
        isNull,
      );
      expect(await stock.listEvents(), isEmpty);
    });

    test('an illegal reason is rejected before any write', () async {
      final stock = harness.repositories.stock;
      await expectLater(
        stock.setStatus(
          ingredientCode: 'salt',
          to: StockStatus.out,
          reason: StockReason.restock,
        ),
        throwsArgumentError,
      );
      expect(await stock.getStatus('salt'), StockStatus.have);
      expect(await stock.listEvents(), isEmpty);
    });

    test('the from-status guard rejects a stale event', () async {
      final stock = harness.repositories.stock;
      await expectLater(
        stock.recordEvent(
          const StockEventDraft(
            ingredientCode: 'salt',
            from: StockStatus.out,
            to: StockStatus.have,
            reason: StockReason.restock,
          ),
        ),
        throwsStateError,
      );
      expect(await stock.getStatus('salt'), StockStatus.have);
      expect(await stock.listEvents(), isEmpty);
    });

    test('a session-linked manual event is refused', () async {
      final stock = harness.repositories.stock;
      await expectLater(
        stock.setStatus(
          ingredientCode: 'salt',
          to: StockStatus.low,
          reason: StockReason.usedSome,
          cookingSessionId: '1',
        ),
        throwsA(anything),
        reason: 'no session row 1 exists yet: the FK rejects the link',
      );
      expect(await stock.getStatus('salt'), StockStatus.have);
    });

    test('events list newest first with limit and offset', () async {
      final stock = harness.repositories.stock;
      await stock.setStatus(
        ingredientCode: 'bay_leaf',
        to: StockStatus.have,
        reason: StockReason.restock,
      );
      await stock.setStatus(
        ingredientCode: 'bay_leaf',
        to: StockStatus.out,
        reason: StockReason.usedUp,
      );
      final events = await stock.listEvents(ingredientCode: 'bay_leaf');
      expect(events, hasLength(2));
      expect(events.first.to, StockStatus.out, reason: 'newest first');
      final page = await stock.listEvents(limit: 1, offset: 1);
      expect(page, hasLength(1));
    });
  });

  group('seed loader', () {
    test('seeding is idempotent across two launches', () async {
      final counts = <String, int>{};
      for (final table in schemaTables) {
        final rows = await harness.db.query(table);
        counts[table] = rows.length;
      }
      expect(counts['recipes'], 3);
      expect(counts['recipe_steps'], 18);
      expect(counts['recipe_step_variants'], 1);
      expect(counts['recipe_ingredients'], 26);
      expect(counts['ingredients'], 15);
      expect(counts['equipment'], 5);
      expect(counts['stock_status'], 15);
      expect(counts['kitchen_equipment'], 2);

      // Second launch: seedIfNeeded again on the same DB…
      await harness.repositories.seedLoader.seedIfNeeded();
      // …and a fresh process opening the same file.
      final relaunched = await reopen(harness, seed: true);
      harness = relaunched;
      for (final table in schemaTables) {
        final rows = await harness.db.query(table);
        expect(rows.length, counts[table], reason: '$table must not grow');
      }
      expect(await harness.seedLoader.seedVersion(), 1);
      expect(await harness.seedLoader.schemaVersion(), 1);
    });

    test('reset restores statuses, equipment and the kitchen name', () async {
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

    test('reset is refused while a cook is in progress', () async {
      await harness.db.insert('cooking_sessions', <String, Object?>{
        'kitchen_id': 1,
        'recipe_id': 1,
        'servings': 4,
      });

      await expectLater(
        harness.repositories.resetDemoData(),
        throwsA(isA<StateError>()),
      );
      // Nothing was half-reset.
      expect(await harness.repositories.stock.listEvents(), isEmpty);
      expect(
        await harness.db.query(
          'cooking_sessions',
          where: 'status = ?',
          whereArgs: <Object?>['in_progress'],
        ),
        hasLength(1),
      );
    });

    test('the mapper helpers keep content keys stable', () {
      expect(dishStampKeyFor('crispy-pork-belly'), 'dish_crispy_pork_belly');
      expect(CookMethod.forEquipment('stovetop').key, 'pan_fry');
      expect(CookMethod.forEquipment('air_fryer').label, 'Air-fry');
      expect(
        CookMethod.forEquipment('microwave_combo').key,
        'microwave_combo',
        reason: 'unknown appliances fall back to their own code',
      );
      expect(decodeStringArray('["garlic","bay_leaf"]'), <String>[
        'garlic',
        'bay_leaf',
      ]);
      expect(
        encodeStringArray(<String>['ingredient:bay_leaf']),
        '["ingredient:bay_leaf"]',
      );
    });
  });
}
