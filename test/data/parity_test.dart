/// Parity contract (`docs/08` §6.4): the fixture repositories and the SQLite
/// repositories must answer identically for the same content, so Phase A and
/// Phase B cannot drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/guide/guide_engine.dart';
import 'package:kusina/domain/models/recipe.dart';
import 'package:kusina/domain/rules/availability_service.dart';

import '../domain/guide/guide_harness.dart' as guide_harness;
import '../helpers/fixture_harness.dart';
import 'sqlite/sqlite_harness.dart';

void main() {
  const service = PresenceAvailabilityService();

  late FixtureHarness fixtures;
  late SqliteHarness sqlite;

  setUp(() async {
    fixtures = await createHarness();
    sqlite = await createSqliteHarness();
  });

  tearDown(() async {
    await sqlite.dispose();
  });

  Future<List<RecipeDetail>> fixtureRecipes() =>
      fixtures.repositories.recipes.listRecipes();

  Future<List<RecipeDetail>> sqliteRecipes() =>
      sqlite.repositories.recipes.listRecipes();

  test('the two backends ship the same recipes', () async {
    final fixture = await fixtureRecipes();
    final database = await sqliteRecipes();

    expect(database, hasLength(fixture.length));
    for (var index = 0; index < fixture.length; index++) {
      final left = fixture[index];
      final right = database[index];
      expect(right.slug, left.slug);
      expect(right.name, left.name);
      expect(right.description, left.description);
      expect(right.cuisine, left.cuisine);
      expect(right.baseServings, left.baseServings);
      expect(right.prepMinutes, left.prepMinutes);
      expect(right.cookMinutes, left.cookMinutes);
      expect(right.difficulty, left.difficulty);
      expect(right.sortOrder, left.sortOrder);
      expect(right.dishStampKey, left.dishStampKey);
      expect(right.requiredEquipmentCodes, left.requiredEquipmentCodes);

      expect(
        right.methods
            .map(
              (method) => <String>[
                method.key,
                method.label,
                method.equipmentCode,
                method.iconKey,
                '${method.isCanonical}',
              ].join('|'),
            )
            .toList(),
        left.methods
            .map(
              (method) => <String>[
                method.key,
                method.label,
                method.equipmentCode,
                method.iconKey,
                '${method.isCanonical}',
              ].join('|'),
            )
            .toList(),
        reason: '${left.slug} methods',
      );

      expect(
        right.lines
            .map(
              (line) => <String>[
                line.ingredientCode,
                line.name,
                '${line.quantity}',
                line.unitCode,
                '${line.isOptional}',
                line.preparationNote ?? '',
              ].join('|'),
            )
            .toList(),
        left.lines
            .map(
              (line) => <String>[
                line.ingredientCode,
                line.name,
                '${line.quantity}',
                line.unitCode,
                '${line.isOptional}',
                line.preparationNote ?? '',
              ].join('|'),
            )
            .toList(),
        reason: '${left.slug} ingredient lines',
      );

      expect(right.steps, hasLength(left.steps.length));
      for (var step = 0; step < left.steps.length; step++) {
        final a = left.steps[step];
        final b = right.steps[step];
        expect(b.stepNumber, a.stepNumber);
        expect(b.kind, a.kind);
        expect(b.instruction, a.instruction);
        expect(b.detail, a.detail);
        expect(b.durationSeconds, a.durationSeconds);
        expect(b.equipmentCode, a.equipmentCode);
        expect(b.ingredientRefs, a.ingredientRefs);
        expect(b.caution, a.caution);
        expect(b.spriteKey, a.spriteKey);
        expect(b.variantGroup, a.variantGroup);
        expect(
          b.variants
              .map(
                (variant) => <String>[
                  variant.methodKey,
                  variant.equipmentCode,
                  variant.instruction ?? '',
                  '${variant.durationSeconds}',
                  variant.spriteKey ?? '',
                  '${variant.priority}',
                ].join('|'),
              )
              .toList(),
          a.variants
              .map(
                (variant) => <String>[
                  variant.methodKey,
                  variant.equipmentCode,
                  variant.instruction ?? '',
                  '${variant.durationSeconds}',
                  variant.spriteKey ?? '',
                  '${variant.priority}',
                ].join('|'),
              )
              .toList(),
          reason: '${left.slug} step ${a.stepNumber} variants',
        );
      }

      // The chosen method resolves to the same pinned implementation.
      for (final method in <String?>[
        if (left.hasMethodChoice) ...left.methods.map((m) => m.key) else null,
      ]) {
        expect(
          right.equipmentCodesFor(method),
          left.equipmentCodesFor(method),
          reason: '${left.slug} equipment for $method',
        );
        for (var step = 0; step < left.steps.length; step++) {
          final a = left.steps[step].resolveFor(left.methodFor(method));
          final b = right.steps[step].resolveFor(right.methodFor(method));
          expect(b?.instruction, a?.instruction);
          expect(b?.durationSeconds, a?.durationSeconds);
          expect(b?.spriteKey, a?.spriteKey);
          expect(b?.equipmentCode, a?.equipmentCode);
          expect(b?.isVariant, a?.isVariant);
        }
      }
    }
  });

  test('the catalog and the demo kitchen match', () async {
    final fixtureIngredients = await fixtures.repositories.stock
        .listIngredients();
    final sqliteIngredients = await sqlite.repositories.stock.listIngredients();

    expect(sqliteIngredients, hasLength(fixtureIngredients.length));
    for (var index = 0; index < fixtureIngredients.length; index++) {
      final left = fixtureIngredients[index];
      final right = sqliteIngredients[index];
      expect(right.code, left.code);
      expect(right.name, left.name);
      expect(right.category, left.category);
      expect(right.defaultStatus, left.defaultStatus);
      expect(right.spriteKey, left.spriteKey);
      expect(right.displayUnit, left.displayUnit);
      // The SQLite read takes the gloss from the bundled fixture catalog, so
      // both backends render "Garlic (Bawang)".
      expect(right.filipinoGloss, left.filipinoGloss);
      expect(right.label, left.label);
    }

    final fixtureEquipment = await fixtures.repositories.equipment.catalog();
    final sqliteEquipment = await sqlite.repositories.equipment.catalog();
    expect(sqliteEquipment, hasLength(fixtureEquipment.length));
    for (var index = 0; index < fixtureEquipment.length; index++) {
      final left = fixtureEquipment[index];
      final right = sqliteEquipment[index];
      expect(right.code, left.code);
      expect(right.name, left.name);
      expect(right.description, left.description);
      expect(right.shipped, left.shipped);
      expect(right.pickerNote, left.pickerNote);
      expect(right.spriteKey, left.spriteKey);
    }

    expect(
      await sqlite.repositories.equipment.ownedIds(),
      await fixtures.repositories.equipment.ownedIds(),
    );
    expect(
      (await sqlite.repositories.kitchen.get()).name,
      (await fixtures.repositories.kitchen.get()).name,
    );

    final fixtureStatuses = await fixtures.repositories.stock.getStatuses(
      fixtureIngredients.map((ingredient) => ingredient.code),
    );
    final sqliteStatuses = await sqlite.repositories.stock.getStatuses(
      sqliteIngredients.map((ingredient) => ingredient.code),
    );
    expect(sqliteStatuses, fixtureStatuses);
  });

  test('availability matches across the four equipment combinations', () async {
    final combos = <Set<String>>[
      <String>{'stovetop', 'air_fryer'},
      <String>{'stovetop'},
      <String>{'air_fryer'},
      <String>{},
    ];

    for (final owned in combos) {
      await fixtures.repositories.equipment.setOwned(owned);
      await sqlite.repositories.equipment.setOwned(owned);

      final fixtureList = await fixtureRecipes();
      final sqliteList = await sqliteRecipes();
      final fixtureStatuses = await fixtures.repositories.stock.getStatuses(
        fixtureList.expand(
          (recipe) => recipe.lines.map((line) => line.ingredientCode),
        ),
      );
      final sqliteStatuses = await sqlite.repositories.stock.getStatuses(
        sqliteList.expand(
          (recipe) => recipe.lines.map((line) => line.ingredientCode),
        ),
      );
      final fixtureOwned = await fixtures.repositories.equipment.ownedIds();
      final sqliteOwned = await sqlite.repositories.equipment.ownedIds();
      expect(sqliteOwned, fixtureOwned);

      for (var index = 0; index < fixtureList.length; index++) {
        final left = fixtureList[index];
        final right = sqliteList[index];
        final methods = <String?>[
          if (!left.hasMethodChoice)
            null
          else
            ...left.methods.map((m) => m.key),
        ];
        for (final method in methods) {
          final leftResult = service.evaluate(
            recipe: left,
            methodKey: method,
            ownedEquipmentCodes: fixtureOwned,
            statuses: fixtureStatuses,
          );
          final rightResult = service.evaluate(
            recipe: right,
            methodKey: method,
            ownedEquipmentCodes: sqliteOwned,
            statuses: sqliteStatuses,
          );
          final label = '${left.slug} $method owned=$owned';
          expect(rightResult.state, leftResult.state, reason: label);
          expect(
            rightResult.missingCodes,
            leftResult.missingCodes,
            reason: label,
          );
          expect(
            rightResult.unconfirmedIngredientCodes,
            leftResult.unconfirmedIngredientCodes,
            reason: label,
          );
          expect(
            rightResult.lowIngredientCodes,
            leftResult.lowIngredientCodes,
            reason: label,
          );
          expect(
            rightResult.requiredEquipmentCodes,
            leftResult.requiredEquipmentCodes,
            reason: label,
          );
        }
      }
    }
  });

  test('step views match for every recipe and method', () async {
    final fixtureEngine = (await guide_harness.createEngineHarness()).engine;
    final sqliteEngine = LocalGuidedCookingEngine(store: sqlite.guideStore);
    final now = DateTime.utc(2026, 1, 1, 9);

    final recipes = await fixtureRecipes();
    for (final recipe in recipes) {
      final methods = <String?>[
        if (!recipe.hasMethodChoice)
          null
        else
          ...recipe.methods.map((m) => m.key),
      ];
      for (final method in methods) {
        final leftStart = await fixtureEngine.start(
          recipeSlug: recipe.slug,
          methodKey: method,
          guideAnyway: true,
          nowUtc: now,
        );
        final rightStart = await sqliteEngine.start(
          recipeSlug: recipe.slug,
          methodKey: method,
          guideAnyway: true,
          nowUtc: now,
        );
        expect(rightStart.session, isNotNull, reason: 'sqlite start');
        expect(leftStart.session, isNotNull, reason: 'fixture start');

        for (var step = 1; step <= recipe.steps.length; step++) {
          final leftView = await fixtureEngine.currentStep(
            sessionId: leftStart.session!.id,
            nowUtc: now,
          );
          final rightView = await sqliteEngine.currentStep(
            sessionId: rightStart.session!.id,
            nowUtc: now,
          );
          final label = '${recipe.slug} $method step $step';
          expect(rightView.stepNumber, leftView.stepNumber, reason: label);
          expect(rightView.instruction, leftView.instruction, reason: label);
          expect(rightView.detail, leftView.detail, reason: label);
          expect(rightView.caution, leftView.caution, reason: label);
          expect(rightView.spriteKey, leftView.spriteKey, reason: label);
          expect(
            rightView.equipmentCode,
            leftView.equipmentCode,
            reason: label,
          );
          expect(
            rightView.ingredientCodes,
            leftView.ingredientCodes,
            reason: label,
          );
          expect(rightView.isVariant, leftView.isVariant, reason: label);
          expect(
            rightView.progressPercent,
            leftView.progressPercent,
            reason: label,
          );
          expect(rightView.timer.phase, leftView.timer.phase, reason: label);

          if (step < recipe.steps.length) {
            await fixtureEngine.advance(
              sessionId: leftStart.session!.id,
              nowUtc: now,
            );
            await sqliteEngine.advance(
              sessionId: rightStart.session!.id,
              nowUtc: now,
            );
          }
        }

        // Tear down so the next method can start (one active session rule).
        await fixtureEngine.abandon(
          sessionId: leftStart.session!.id,
          confirmed: true,
          nowUtc: now,
        );
        await sqliteEngine.abandon(
          sessionId: rightStart.session!.id,
          confirmed: true,
          nowUtc: now,
        );
      }
    }
  });
}
