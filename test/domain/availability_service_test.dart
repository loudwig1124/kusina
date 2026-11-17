import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/recipe.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';

import '../helpers/fixture_harness.dart';

void main() {
  const service = PresenceAvailabilityService();

  late RecipeDetail adobo;
  late RecipeDetail sinangag;
  late RecipeDetail porkBelly;
  late Map<String, StockStatus> demoStatuses;
  late Set<String> demoEquipment;

  setUpAll(() async {
    final harness = await createHarness();
    adobo = harness.bundle.recipeFor('chicken-adobo')!;
    sinangag = harness.bundle.recipeFor('sinangag')!;
    porkBelly = harness.bundle.recipeFor('crispy-pork-belly')!;
    demoStatuses = harness.statuses;
    demoEquipment = harness.ownedEquipmentCodes;
  });

  AvailabilityResult evaluate(
    RecipeDetail recipe, {
    String? methodKey,
    Set<String>? owned,
    Map<String, StockStatus>? statuses,
  }) => service.evaluate(
    recipe: recipe,
    methodKey: methodKey,
    ownedEquipmentCodes: owned ?? demoEquipment,
    statuses: statuses ?? demoStatuses,
  );

  group('pork belly: the four equipment combinations', () {
    test('both appliances owned: both methods are ready', () {
      final both = <String>{'stovetop', 'air_fryer'};
      final panFry = evaluate(porkBelly, methodKey: 'pan_fry', owned: both);
      final airFry = evaluate(porkBelly, methodKey: 'air_fry', owned: both);

      expect(panFry.state, AvailabilityState.ready);
      expect(airFry.state, AvailabilityState.ready);
      expect(panFry.requiredEquipmentCodes, <String>{'stovetop'});
      expect(airFry.requiredEquipmentCodes, <String>{'stovetop', 'air_fryer'});
      expect(panFry.missing, isEmpty);
      expect(airFry.missing, isEmpty);
    });

    test('stovetop only: Pan-fry ready, Air-fry missing the air fryer', () {
      final stovetopOnly = <String>{'stovetop'};
      final panFry = evaluate(
        porkBelly,
        methodKey: 'pan_fry',
        owned: stovetopOnly,
      );
      final airFry = evaluate(
        porkBelly,
        methodKey: 'air_fry',
        owned: stovetopOnly,
      );

      expect(panFry.state, AvailabilityState.ready);
      expect(airFry.state, AvailabilityState.blocked);
      expect(airFry.missingCodes, <String>['equipment:air_fryer']);
      expect(airFry.startActionLabel, 'Guide me anyway');
    });

    test('air fryer only: Pan-fry stays blocked on the stovetop', () {
      final airFryerOnly = <String>{'air_fryer'};
      final panFry = evaluate(
        porkBelly,
        methodKey: 'pan_fry',
        owned: airFryerOnly,
      );
      final airFry = evaluate(
        porkBelly,
        methodKey: 'air_fry',
        owned: airFryerOnly,
      );

      expect(panFry.state, AvailabilityState.blocked);
      expect(panFry.missingCodes, <String>['equipment:stovetop']);
      // The air fryer is owned here, so only the shared stovetop is missing.
      expect(airFry.state, AvailabilityState.blocked);
      expect(airFry.missingCodes, <String>['equipment:stovetop']);
    });

    test('no appliances: both methods are blocked, never re-selected', () {
      final none = <String>{};
      final panFry = evaluate(porkBelly, methodKey: 'pan_fry', owned: none);
      final airFry = evaluate(porkBelly, methodKey: 'air_fry', owned: none);

      expect(panFry.state, AvailabilityState.blocked);
      expect(airFry.state, AvailabilityState.blocked);
      expect(panFry.missingCodes, <String>['equipment:stovetop']);
      expect(airFry.missingCodes, <String>[
        'equipment:air_fryer',
        'equipment:stovetop',
      ]);
    });

    test('the picked method keeps its own appliance, never the other one', () {
      // A stovetop kitchen picking Pan-fry never sees "missing air fryer".
      expect(
        evaluate(
          porkBelly,
          methodKey: 'pan_fry',
          owned: <String>{'stovetop'},
        ).missingCodes,
        isEmpty,
      );
      // The same kitchen picking Air-fry is blocked on the air fryer it asked for.
      expect(
        evaluate(
          porkBelly,
          methodKey: 'air_fry',
          owned: <String>{'stovetop'},
        ).missingCodes,
        <String>['equipment:air_fryer'],
      );
    });
  });

  group('presence rule', () {
    test('out blocks a required ingredient', () {
      final result = evaluate(adobo);
      expect(result.state, AvailabilityState.blocked);
      expect(result.missingCodes, <String>['ingredient:bay_leaf']);
    });

    test('unknown does not block; it asks for confirmation', () {
      final statuses = <String, StockStatus>{
        ...demoStatuses,
        'bay_leaf': StockStatus.have,
        'garlic': StockStatus.unknown,
      };
      final result = evaluate(adobo, statuses: statuses);

      expect(result.state, AvailabilityState.needsConfirmation);
      expect(result.missingCodes, isEmpty);
      expect(result.unconfirmedIngredientCodes, <String>['garlic']);
      expect(result.startActionLabel, 'Start and confirm items');
    });

    test('low is available but warns', () {
      final statuses = <String, StockStatus>{
        ...demoStatuses,
        'bay_leaf': StockStatus.have,
        'vinegar': StockStatus.low,
      };
      final result = evaluate(adobo, statuses: statuses);

      expect(result.state, AvailabilityState.ready);
      expect(result.lowIngredientCodes, <String>['vinegar']);
      expect(result.startActionLabel, 'Start cooking');
    });

    test('an optional ingredient never blocks and never warns', () {
      final statuses = <String, StockStatus>{
        ...demoStatuses,
        'cooking_oil': StockStatus.out,
        'sugar': StockStatus.unknown,
        'black_pepper': StockStatus.low,
      };
      final result = evaluate(adobo, statuses: statuses);

      // bay_leaf is still out, so the only missing code is the required one.
      expect(result.missingCodes, <String>['ingredient:bay_leaf']);
      expect(result.unconfirmedIngredientCodes, isEmpty);
      expect(result.lowIngredientCodes, isEmpty);

      // The same optionals on a ready dish keep it ready.
      final restocked = <String, StockStatus>{
        ...statuses,
        'bay_leaf': StockStatus.have,
      };
      expect(
        evaluate(adobo, statuses: restocked).state,
        AvailabilityState.ready,
      );
    });

    test('a missing stock row reads as unknown, never as out', () {
      final statuses = <String, StockStatus>{...demoStatuses}
        ..remove('vinegar');
      final result = evaluate(adobo, statuses: statuses);

      expect(result.missingCodes, <String>['ingredient:bay_leaf']);
      expect(result.unconfirmedIngredientCodes, <String>['vinegar']);
    });

    test('missing requirements are stable codes, sorted', () {
      final statuses = <String, StockStatus>{
        ...demoStatuses,
        'garlic': StockStatus.out,
      };
      final result = evaluate(adobo, owned: <String>{}, statuses: statuses);

      expect(result.missingCodes, <String>[
        'equipment:stovetop',
        'ingredient:bay_leaf',
        'ingredient:garlic',
      ]);
      expect(result.guideAnywayAllowed, isTrue);
      expect(result.startActionLabel, 'Guide me anyway');
    });
  });

  group('no auto-selection', () {
    test('a method dish needs the cook pick', () {
      expect(() => evaluate(porkBelly), throwsA(isA<ArgumentError>()));
    });

    test('an unknown method key is rejected', () {
      expect(
        () => evaluate(porkBelly, methodKey: 'deep_fry'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a single-path dish rejects a method key', () {
      expect(
        () => evaluate(adobo, methodKey: 'pan_fry'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a single-path dish evaluates with no method', () {
      expect(evaluate(sinangag).state, AvailabilityState.ready);
      expect(evaluate(sinangag).methodKey, isNull);
    });
  });

  group('evaluateAll list badges', () {
    test('demo kitchen: Adobo missing, Sinangag ready, pork belly ready', () {
      final results = service.evaluateAll(
        recipes: <RecipeDetail>[adobo, sinangag, porkBelly],
        ownedEquipmentCodes: demoEquipment,
        statuses: demoStatuses,
      );

      expect(results.keys, <String>[
        'chicken-adobo',
        'sinangag',
        'crispy-pork-belly',
      ]);
      expect(results['chicken-adobo']!.state, AvailabilityState.blocked);
      expect(results['chicken-adobo']!.missingCodes, <String>[
        'ingredient:bay_leaf',
      ]);
      expect(results['sinangag']!.state, AvailabilityState.ready);
      expect(results['crispy-pork-belly']!.state, AvailabilityState.ready);
    });

    test('the list badge names the best method and never pins anything', () {
      final results = service.evaluateAll(
        recipes: <RecipeDetail>[porkBelly],
        ownedEquipmentCodes: <String>{'stovetop'},
        statuses: demoStatuses,
      );
      final belly = results['crispy-pork-belly']!;

      // Pan-fry is ready while Air-fry is blocked: the badge reports Pan-fry.
      expect(belly.state, AvailabilityState.ready);
      expect(belly.methodKey, 'pan_fry');
    });

    test('a fully blocked dish reports blocked', () {
      final results = service.evaluateAll(
        recipes: <RecipeDetail>[porkBelly],
        ownedEquipmentCodes: <String>{},
        statuses: demoStatuses,
      );

      expect(results['crispy-pork-belly']!.state, AvailabilityState.blocked);
    });
  });
}
