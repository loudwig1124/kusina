import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/data/repositories/fixture/fixture_bundle.dart';
import 'package:kusina/data/repositories/fixture/fixture_source.dart';
import 'package:kusina/domain/models/recipe.dart';
import 'package:kusina/domain/models/stock.dart';

import '../helpers/fixture_harness.dart';

void main() {
  late FixtureBundle bundle;

  setUpAll(() async {
    bundle = await loadFixtureBundle();
  });

  test('parses the shipped content counts', () {
    expect(bundle.seedVersion, FixtureBundle.supportedSeedVersion);
    expect(bundle.ingredients, hasLength(15));
    expect(bundle.equipment, hasLength(5));
    expect(bundle.recipes, hasLength(3));
    expect(bundle.kitchen.name, "Maria's Kitchen");
    expect(bundle.ownedEquipmentCodes, <String>{'stovetop', 'air_fryer'});
    expect(bundle.statuses, hasLength(15));
  });

  test('recipes are ordered by sortOrder', () {
    expect(bundle.recipes.map((recipe) => recipe.slug).toList(), <String>[
      'chicken-adobo',
      'sinangag',
      'crispy-pork-belly',
    ]);
    expect(bundle.recipes.map((recipe) => recipe.sortOrder).toList(), <int>[
      1,
      2,
      3,
    ]);
  });

  test('demo stock is the docs/06 section 7 tri-state', () {
    final counts = <StockStatus, int>{};
    for (final status in bundle.statuses.values) {
      counts[status] = (counts[status] ?? 0) + 1;
    }
    expect(counts[StockStatus.have], 11);
    expect(counts[StockStatus.low], 1);
    expect(counts[StockStatus.out], 1);
    expect(counts[StockStatus.unknown], 2);
    expect(bundle.statuses['bay_leaf'], StockStatus.out);
    expect(bundle.statuses['spring_onion'], StockStatus.low);
    expect(bundle.statuses['calamansi'], StockStatus.unknown);
  });

  test('every ingredient has the full catalog shape', () {
    final garlic = bundle.ingredientFor('garlic')!;
    expect(garlic.name, 'Garlic');
    expect(garlic.filipinoGloss, 'Bawang');
    expect(garlic.category, 'produce');
    expect(garlic.displayUnit, 'clove');
    expect(garlic.defaultStatus, StockStatus.unknown);
    expect(garlic.spriteKey, 'ing_garlic');
  });

  test('equipment carries the shipped flag and picker note', () {
    final airFryer = bundle.equipmentFor('air_fryer')!;
    expect(airFryer.shipped, isTrue);
    expect(airFryer.pickerNote, isNull);
    final grill = bundle.equipmentFor('grill')!;
    expect(grill.shipped, isFalse);
    expect(grill.pickerNote, 'No dishes yet');
  });

  test('Chicken Adobo is the 7-step canonical dish', () {
    final adobo = bundle.recipeFor('chicken-adobo')!;
    expect(adobo.name, 'Chicken Adobo');
    expect(adobo.steps, hasLength(7));
    expect(adobo.hasMethodChoice, isFalse);
    expect(adobo.requiredEquipmentCodes, <String>['stovetop']);
    expect(adobo.equipmentCodesFor(null), <String>{'stovetop'});
    expect(adobo.requiredLines.map((line) => line.ingredientCode), <String>[
      'chicken_thighs',
      'soy_sauce',
      'vinegar',
      'garlic',
      'bay_leaf',
    ]);
    expect(adobo.optionalLines.map((line) => line.ingredientCode), <String>[
      'cooking_oil',
      'black_pepper',
      'sugar',
    ]);
    expect(adobo.steps.first.kind, StepKind.prep);
    expect(adobo.steps.last.kind, StepKind.finish);
    expect(adobo.steps[1].durationSeconds, 480);
    expect(adobo.steps[4].durationSeconds, 1500);
  });

  test('Crispy Pork Belly ships two explicit methods', () {
    final pork = bundle.recipeFor('crispy-pork-belly')!;
    expect(pork.name, 'Crispy Pork Belly');
    expect(pork.hasMethodChoice, isTrue);
    expect(pork.requiredEquipmentCodes, isEmpty);
    expect(pork.methods.map((method) => method.key), <String>[
      'pan_fry',
      'air_fry',
    ]);
    expect(pork.methods.map((method) => method.label), <String>[
      'Pan-fry',
      'Air-fry',
    ]);
    expect(pork.methods.map((method) => method.equipmentCode), <String>[
      'stovetop',
      'air_fryer',
    ]);
    expect(pork.canonicalMethod!.key, 'air_fry');
    expect(pork.methodFor('pan_fry')!.isCanonical, isFalse);

    // The boil is shared, the crisp step is the only delta.
    expect(pork.steps, hasLength(6));
    final methodSteps = pork.steps.where((step) => step.isMethodDependent);
    expect(methodSteps, hasLength(1));
    expect(methodSteps.single.stepNumber, 5);
    expect(methodSteps.single.variantGroup, 'cook_method');
  });

  test('the chosen method resolves its own crisp step', () {
    final pork = bundle.recipeFor('crispy-pork-belly')!;
    final crisp = pork.steps[4];

    final airFry = crisp.resolveFor(pork.methodFor('air_fry'))!;
    expect(airFry.isVariant, isFalse);
    expect(airFry.equipmentCode, 'air_fryer');
    expect(airFry.durationSeconds, 1200);
    expect(airFry.spriteKey, 'step_cook_air_fryer');
    expect(airFry.instruction, contains('air-fry'));

    final panFry = crisp.resolveFor(pork.methodFor('pan_fry'))!;
    expect(panFry.isVariant, isTrue);
    expect(panFry.equipmentCode, 'stovetop');
    expect(panFry.durationSeconds, 720);
    expect(panFry.spriteKey, 'step_cook_stovetop');
    expect(panFry.instruction, contains('pan'));
    expect(panFry.variant!.priority, 10);
  });

  test('equipment needs are the union of the chosen path', () {
    final pork = bundle.recipeFor('crispy-pork-belly')!;
    expect(pork.equipmentCodesFor('pan_fry'), <String>{'stovetop'});
    expect(pork.equipmentCodesFor('air_fry'), <String>{
      'stovetop',
      'air_fryer',
    });
  });

  test('a method-dependent step refuses to resolve without a pick', () {
    final pork = bundle.recipeFor('crispy-pork-belly')!;
    expect(() => pork.steps[4].resolveFor(null), throwsArgumentError);
    expect(() => pork.equipmentCodesFor(null), throwsArgumentError);
  });

  test('display quantities are labels, not inputs', () {
    final adobo = bundle.recipeFor('chicken-adobo')!;
    final chicken = adobo.lines.firstWhere(
      (line) => line.ingredientCode == 'chicken_thighs',
    );
    expect(chicken.quantityLabel, '1000 g');
    expect(chicken.isOptional, isFalse);
    expect(chicken.preparationNote, 'Bone-in, cut into serving pieces');
  });

  test('broken content is rejected with a clear error', () {
    expect(
      () => FixtureBundle.parse(const <String, String>{}),
      throwsFormatException,
    );
  });

  test(
    'AssetFixtureSource loads the same content as the disk source',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fromAssets = FixtureBundle.parse(
        await const AssetFixtureSource().load(),
      );
      final fromDisk = await loadFixtureBundle();

      expect(fromAssets.recipes.length, fromDisk.recipes.length);
      expect(fromAssets.ingredients.length, fromDisk.ingredients.length);
      expect(
        fromAssets.recipes.map((recipe) => recipe.slug),
        fromDisk.recipes.map((recipe) => recipe.slug),
      );
    },
  );
}
