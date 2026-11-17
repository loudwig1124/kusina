/// Engine test harness: the fixture repositories behind the in-memory guide
/// store, a fixed clock and a deterministic session id.
library;

import 'package:kusina/data/repositories/fixture/fixture_data.dart';
import 'package:kusina/domain/guide/guide_engine.dart';
import 'package:kusina/domain/guide/guide_store.dart';
import 'package:kusina/domain/models/recipe.dart';
import 'package:kusina/domain/models/stock.dart';

import '../../helpers/fixture_harness.dart';

/// Fixed instants: 2026-01-01T09:00:00Z is "now" for every test.
final DateTime testNow = DateTime.utc(2026, 1, 1, 9);

class EngineHarness {
  EngineHarness({
    required this.fixtures,
    required this.store,
    required this.engine,
    required this.sessions,
    required this.recipeOverrides,
  });

  final FixtureHarness fixtures;
  final InMemoryGuideStore store;
  final LocalGuidedCookingEngine engine;
  final List<String> sessions;

  /// Per-slug content overrides: writing here simulates an edited seed without
  /// rebuilding the harness, so pinning can be proven on a live session.
  final Map<String, RecipeDetail> recipeOverrides;

  FixtureData get data => fixtures.data;

  /// The recipe content the store serves; tests can swap it to prove pinning.
  RecipeReader get reader => store.recipeReader;

  Future<List<StockEvent>> eventsFor(String ingredientCode) =>
      fixtures.repositories.stock.listEvents(ingredientCode: ingredientCode);

  Future<List<StockEvent>> allEvents() =>
      fixtures.repositories.stock.listEvents();

  Future<StockStatus> statusOf(String ingredientCode) =>
      fixtures.repositories.stock.getStatus(ingredientCode);

  Future<Map<String, StockStatus>> statusesOf(List<String> codes) =>
      fixtures.repositories.stock.getStatuses(codes);

  Future<RecipeDetail?> recipe(String slug) =>
      fixtures.repositories.recipes.findBySlug(slug);
}

Future<EngineHarness> createEngineHarness({
  Set<String>? ownedEquipment,
  Map<String, StockStatus>? statuses,
}) async {
  final fixtures = await createHarness(
    ownedEquipment: ownedEquipment,
    statuses: statuses,
  );
  final sessionIds = <String>[];
  final recipeOverrides = <String, RecipeDetail>{};
  final store = InMemoryGuideStore(
    recipeReader: (slug) async =>
        recipeOverrides[slug] ??
        await fixtures.repositories.recipes.findBySlug(slug),
    statusReader: (codes) => fixtures.repositories.stock.getStatuses(codes),
    ownedEquipmentReader: () => fixtures.repositories.equipment.ownedIds(),
    statusWriter: (code, to, reason, {cookingSessionId, note}) async {
      await fixtures.repositories.stock.setStatus(
        ingredientCode: code,
        to: to,
        reason: reason,
        cookingSessionId: cookingSessionId,
        note: note,
      );
    },
  );
  final engine = LocalGuidedCookingEngine(
    store: store,
    newSessionId: () {
      final id = 'session-${sessionIds.length + 1}';
      sessionIds.add(id);
      return id;
    },
  );
  return EngineHarness(
    fixtures: fixtures,
    store: store,
    engine: engine,
    sessions: sessionIds,
    recipeOverrides: recipeOverrides,
  );
}

/// A recipe with its canonical flags swapped, to prove a running session does
/// not re-plan from live content.
RecipeDetail withCanonicalMethod(RecipeDetail recipe, String methodKey) {
  return RecipeDetail(
    slug: recipe.slug,
    name: recipe.name,
    description: recipe.description,
    cuisine: recipe.cuisine,
    baseServings: recipe.baseServings,
    prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes,
    difficulty: recipe.difficulty,
    sortOrder: recipe.sortOrder,
    dishStampKey: recipe.dishStampKey,
    requiredEquipmentCodes: recipe.requiredEquipmentCodes,
    methods: <RecipeMethod>[
      for (final method in recipe.methods)
        RecipeMethod(
          key: method.key,
          label: method.label,
          equipmentCode: method.equipmentCode,
          iconKey: method.iconKey,
          isCanonical: method.key == methodKey,
        ),
    ],
    lines: recipe.lines,
    steps: recipe.steps,
  );
}

/// A recipe with one variant's instruction rewritten (simulating an edited seed).
RecipeDetail withVariantInstruction(
  RecipeDetail recipe,
  int stepNumber,
  String methodKey,
  String instruction,
) {
  return RecipeDetail(
    slug: recipe.slug,
    name: recipe.name,
    description: recipe.description,
    cuisine: recipe.cuisine,
    baseServings: recipe.baseServings,
    prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes,
    difficulty: recipe.difficulty,
    sortOrder: recipe.sortOrder,
    dishStampKey: recipe.dishStampKey,
    requiredEquipmentCodes: recipe.requiredEquipmentCodes,
    methods: recipe.methods,
    lines: recipe.lines,
    steps: <RecipeStep>[
      for (final step in recipe.steps)
        if (step.stepNumber == stepNumber)
          RecipeStep(
            stepNumber: step.stepNumber,
            kind: step.kind,
            instruction: step.instruction,
            detail: step.detail,
            durationSeconds: step.durationSeconds,
            equipmentCode: step.equipmentCode,
            ingredientRefs: step.ingredientRefs,
            caution: step.caution,
            spriteKey: step.spriteKey,
            variantGroup: step.variantGroup,
            variants: <StepVariant>[
              for (final variant in step.variants)
                variant.methodKey == methodKey
                    ? StepVariant(
                        methodKey: variant.methodKey,
                        equipmentCode: variant.equipmentCode,
                        instruction: instruction,
                        durationSeconds: variant.durationSeconds,
                        spriteKey: variant.spriteKey,
                        priority: variant.priority,
                      )
                    : variant,
            ],
          )
        else
          step,
    ],
  );
}

/// A recipe whose steps carry different copy (simulating an edited seed).
RecipeDetail withStepInstruction(
  RecipeDetail recipe,
  int stepNumber,
  String instruction,
) {
  return RecipeDetail(
    slug: recipe.slug,
    name: recipe.name,
    description: recipe.description,
    cuisine: recipe.cuisine,
    baseServings: recipe.baseServings,
    prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes,
    difficulty: recipe.difficulty,
    sortOrder: recipe.sortOrder,
    dishStampKey: recipe.dishStampKey,
    requiredEquipmentCodes: recipe.requiredEquipmentCodes,
    methods: recipe.methods,
    lines: recipe.lines,
    steps: <RecipeStep>[
      for (final step in recipe.steps)
        if (step.stepNumber == stepNumber)
          RecipeStep(
            stepNumber: step.stepNumber,
            kind: step.kind,
            instruction: instruction,
            detail: step.detail,
            durationSeconds: step.durationSeconds,
            equipmentCode: step.equipmentCode,
            ingredientRefs: step.ingredientRefs,
            caution: step.caution,
            spriteKey: step.spriteKey,
            variantGroup: step.variantGroup,
            variants: step.variants,
          )
        else
          step,
    ],
  );
}
