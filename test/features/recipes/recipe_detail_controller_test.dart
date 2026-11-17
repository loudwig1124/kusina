import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';
import 'package:kusina/features/recipes/recipe_detail_controller.dart';

import '../../helpers/fixture_harness.dart';

void main() {
  late FixtureHarness harness;

  setUp(() async {
    harness = await createHarness();
  });

  RecipeDetailController controllerFor(
    String slug, {
    String? methodKey,
    Set<String>? owned,
    Map<String, StockStatus>? statuses,
  }) {
    return RecipeDetailController(
      recipe: harness.bundle.recipeFor(slug)!,
      availabilityService: const PresenceAvailabilityService(),
      ownedEquipmentCodes: owned ?? harness.ownedEquipmentCodes,
      statuses: statuses ?? harness.statuses,
      selectedMethodKey: methodKey,
    );
  }

  test('a method dish starts with no pick and no availability', () {
    final controller = controllerFor('crispy-pork-belly');

    expect(controller.selectedMethodKey, isNull);
    expect(controller.needsMethodChoice, isTrue);
    expect(controller.canStart, isFalse);
    expect(controller.selectedAvailability, isNull);
    expect(controller.primaryLabel, 'Choose Pan-fry or Air-fry');
    expect(controller.methodAvailability.keys, <String>['pan_fry', 'air_fry']);
    expect(
      controller.methodAvailability['pan_fry']!.state,
      AvailabilityState.ready,
    );
  });

  test('the pick drives the label and the panel', () {
    final airFry = controllerFor('crispy-pork-belly', methodKey: 'air_fry');

    expect(airFry.selectedMethodKey, 'air_fry');
    expect(airFry.needsMethodChoice, isFalse);
    expect(airFry.canStart, isTrue);
    expect(airFry.primaryLabel, 'Start cooking');
    expect(airFry.selectedAvailability!.methodKey, 'air_fry');
    expect(airFry.selectedAvailability!.requiredEquipmentCodes, <String>{
      'stovetop',
      'air_fryer',
    });

    final panFry = controllerFor('crispy-pork-belly', methodKey: 'pan_fry');
    expect(panFry.selectedAvailability!.methodKey, 'pan_fry');
    expect(panFry.selectedAvailability!.requiredEquipmentCodes, <String>{
      'stovetop',
    });
  });

  test('the label follows the picked method state', () {
    final stovetopOnly = <String>{'stovetop'};

    final airFry = controllerFor(
      'crispy-pork-belly',
      methodKey: 'air_fry',
      owned: stovetopOnly,
    );
    expect(airFry.selectedAvailability!.state, AvailabilityState.blocked);
    expect(airFry.primaryLabel, 'Guide me anyway');
    expect(airFry.canStart, isTrue);

    final panFry = controllerFor(
      'crispy-pork-belly',
      methodKey: 'pan_fry',
      owned: stovetopOnly,
    );
    expect(panFry.selectedAvailability!.state, AvailabilityState.ready);
    expect(panFry.primaryLabel, 'Start cooking');
  });

  test('the per-method badges are computed for each method path', () {
    final controller = controllerFor(
      'crispy-pork-belly',
      owned: <String>{'stovetop'},
    );

    expect(
      controller.methodAvailability['pan_fry']!.state,
      AvailabilityState.ready,
    );
    expect(
      controller.methodAvailability['air_fry']!.state,
      AvailabilityState.blocked,
    );
    expect(controller.availabilityFor('air_fry')!.missingCodes, <String>[
      'equipment:air_fryer',
    ]);
  });

  test('unknown required ingredients change the start label, not the pick', () {
    final controller = controllerFor(
      'chicken-adobo',
      statuses: <String, StockStatus>{
        ...harness.statuses,
        'bay_leaf': StockStatus.have,
        'garlic': StockStatus.unknown,
      },
    );

    expect(
      controller.selectedAvailability!.state,
      AvailabilityState.needsConfirmation,
    );
    expect(controller.primaryLabel, 'Start and confirm items');
  });

  test('a stock change flips a single-path dish', () {
    final blocked = controllerFor('chicken-adobo');
    expect(blocked.selectedAvailability!.state, AvailabilityState.blocked);
    expect(blocked.primaryLabel, 'Guide me anyway');

    final ready = controllerFor(
      'chicken-adobo',
      statuses: <String, StockStatus>{
        ...harness.statuses,
        'bay_leaf': StockStatus.have,
      },
    );
    expect(ready.selectedAvailability!.state, AvailabilityState.ready);
    expect(ready.primaryLabel, 'Start cooking');
  });

  test('an equipment change re-evaluates the open pick', () {
    final ready = controllerFor('crispy-pork-belly', methodKey: 'air_fry');
    expect(ready.selectedAvailability!.state, AvailabilityState.ready);

    final toggled = controllerFor(
      'crispy-pork-belly',
      methodKey: 'air_fry',
      owned: <String>{'stovetop'},
    );
    expect(toggled.selectedMethodKey, 'air_fry');
    expect(toggled.selectedAvailability!.state, AvailabilityState.blocked);
    expect(toggled.primaryLabel, 'Guide me anyway');
  });

  test('an unknown method key is rejected', () {
    expect(
      () => controllerFor('crispy-pork-belly', methodKey: 'deep_fry'),
      throwsArgumentError,
    );
  });

  test('a single-path dish needs no pick', () {
    final controller = controllerFor('sinangag');
    expect(controller.needsMethodChoice, isFalse);
    expect(controller.canStart, isTrue);
    expect(controller.selectedAvailability!.state, AvailabilityState.ready);
    expect(controller.primaryLabel, 'Start cooking');
    expect(controller.methodAvailability, isEmpty);
  });

  test('a single-path dish ignores a method pick', () {
    expect(
      () => controllerFor('sinangag', methodKey: 'pan_fry'),
      throwsArgumentError,
    );
  });
}
