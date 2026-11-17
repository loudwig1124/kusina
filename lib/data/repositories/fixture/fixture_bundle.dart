/// Parses the t4 content JSON (`assets/fixtures/`) into immutable domain models.
///
/// Lives beside the fixture repositories (`docs/08` §3.1): the JSON itself is
/// the `assets/fixtures/` content source, not a second copy under `lib/`.
///
/// Pure Dart and Flutter-free: the bundle is built once at the composition root
/// (`lib/app/di.dart`) from an asset source, and tests build it from disk. The
/// same file shapes are the Phase B seed source, so parity is a data question.
library;

import 'dart:convert';

import '../../../domain/models/catalog.dart';
import '../../../domain/models/kitchen.dart';
import '../../../domain/models/recipe.dart';
import '../../../domain/models/stock.dart';

/// Immutable snapshot of the four fixture files.
///
/// Files are matched by basename so the loader does not care which directory
/// the asset source read them from; anything under a `recipes/` segment is a
/// recipe file.
class FixtureBundle {
  const FixtureBundle({
    required this.seedVersion,
    required this.ingredients,
    required this.equipment,
    required this.kitchen,
    required this.ownedEquipmentCodes,
    required this.statuses,
    required this.recipes,
  });

  static const int supportedSeedVersion = 1;

  static const String ingredientsFile = 'ingredients.json';
  static const String equipmentFile = 'equipment.json';
  static const String kitchenFile = 'kitchen_demo.json';

  final int seedVersion;
  final List<Ingredient> ingredients;
  final List<Equipment> equipment;
  final Kitchen kitchen;

  /// Owned appliance codes from the demo kitchen.
  final Set<String> ownedEquipmentCodes;

  /// Demo tri-state map: one entry per catalog ingredient.
  final Map<String, StockStatus> statuses;

  /// The three dishes, ordered by `sortOrder` (Adobo 1, Sinangag 2, pork 3).
  final List<RecipeDetail> recipes;

  Map<String, Ingredient> get _ingredientsByCode => {
    for (final ingredient in ingredients) ingredient.code: ingredient,
  };

  Ingredient? ingredientFor(String code) => _ingredientsByCode[code];

  Equipment? equipmentFor(String code) {
    for (final item in equipment) {
      if (item.code == code) {
        return item;
      }
    }
    return null;
  }

  RecipeDetail? recipeFor(String slug) {
    for (final recipe in recipes) {
      if (recipe.slug == slug) {
        return recipe;
      }
    }
    return null;
  }

  /// Builds the bundle from a `path -> JSON text` map. Throws [FormatException]
  /// when a required file is missing or a payload breaks the authoring rules
  /// this model depends on.
  factory FixtureBundle.parse(Map<String, String> files) {
    String? ingredientsJson;
    String? equipmentJson;
    String? kitchenJson;
    final recipeJsons = <String, String>{};

    for (final entry in files.entries) {
      final name = entry.key.split('/').last;
      if (name == ingredientsFile) {
        ingredientsJson = entry.value;
      } else if (name == equipmentFile) {
        equipmentJson = entry.value;
      } else if (name == kitchenFile) {
        kitchenJson = entry.value;
      } else if (entry.key.contains('/recipes/') && name.endsWith('.json')) {
        recipeJsons[name] = entry.value;
      }
    }

    if (ingredientsJson == null) {
      throw const FormatException('fixture set is missing ingredients.json');
    }
    if (equipmentJson == null) {
      throw const FormatException('fixture set is missing equipment.json');
    }
    if (kitchenJson == null) {
      throw const FormatException('fixture set is missing kitchen_demo.json');
    }
    if (recipeJsons.isEmpty) {
      throw const FormatException('fixture set has no recipes/*.json files');
    }

    final ingredients = _parseIngredients(
      _decode(ingredientsJson, 'ingredients.json'),
    );
    final equipment = _parseEquipment(_decode(equipmentJson, 'equipment.json'));
    final kitchenPayload = _asObject(
      _decode(kitchenJson, 'kitchen_demo.json'),
      'kitchen_demo.json',
    );

    final ingredientsByCode = {
      for (final ingredient in ingredients) ingredient.code: ingredient,
    };
    final equipmentByCode = {for (final item in equipment) item.code: item};

    final recipes = <RecipeDetail>[];
    final recipeNames = recipeJsons.keys.toList()..sort();
    for (final name in recipeNames) {
      recipes.add(
        _parseRecipe(
          _decode(recipeJsons[name]!, name),
          ingredientsByCode: ingredientsByCode,
          equipmentByCode: equipmentByCode,
        ),
      );
    }
    recipes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final kitchen = _parseKitchen(kitchenPayload);
    final owned = _parseOwnedEquipment(kitchenPayload, equipmentByCode);
    final statuses = _parseStatuses(kitchenPayload, ingredientsByCode);

    final seedVersion = _readSeedVersion(kitchenPayload, 'kitchen_demo.json');
    return FixtureBundle(
      seedVersion: seedVersion,
      ingredients: List.unmodifiable(ingredients),
      equipment: List.unmodifiable(equipment),
      kitchen: kitchen,
      ownedEquipmentCodes: Set.unmodifiable(owned),
      statuses: Map.unmodifiable(statuses),
      recipes: List.unmodifiable(recipes),
    );
  }

  static Object? _decode(String json, String label) {
    try {
      return jsonDecode(json);
    } on FormatException catch (error) {
      throw FormatException('$label is not valid JSON: ${error.message}');
    }
  }

  static int _readSeedVersion(Object? payload, String label) {
    if (payload is! Map<String, Object?>) {
      throw FormatException('$label must be a JSON object');
    }
    final version = payload['seedVersion'];
    if (version is! int) {
      throw FormatException('$label.seedVersion must be an integer');
    }
    if (version != supportedSeedVersion) {
      throw FormatException(
        '$label.seedVersion $version is not supported '
        '(expected $supportedSeedVersion)',
      );
    }
    return version;
  }

  static Map<String, Object?> _asObject(Object? value, String label) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$label must be a JSON object');
    }
    return value;
  }

  static List<Object?> _asList(Object? value, String label) {
    if (value is! List<Object?>) {
      throw FormatException('$label must be a JSON array');
    }
    return value;
  }

  static String _asString(Object? value, String label) {
    if (value is! String || value.isEmpty) {
      throw FormatException('$label must be a non-empty string');
    }
    return value;
  }

  static String? _asOptionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static num _asNum(Object? value, String label) {
    if (value is! num) {
      throw FormatException('$label must be a number');
    }
    return value;
  }

  static int _asInt(Object? value, String label) {
    if (value is! int) {
      throw FormatException('$label must be an integer');
    }
    return value;
  }

  static List<Ingredient> _parseIngredients(Object? payload) {
    final root = _asObject(payload, 'ingredients.json');
    final rows = _asList(root['ingredients'], 'ingredients.json.ingredients');
    return [
      for (final row in rows)
        _parseIngredient(_asObject(row, 'ingredients.json.ingredients[]')),
    ];
  }

  static Ingredient _parseIngredient(Map<String, Object?> row) {
    return Ingredient(
      code: _asString(row['id'], 'ingredient.id'),
      name: _asString(row['name'], 'ingredient.name'),
      filipinoGloss: _asString(
        row['filipinoGloss'],
        'ingredient.filipinoGloss',
      ),
      category: _asString(row['category'], 'ingredient.category'),
      displayUnit: _asString(row['displayUnit'], 'ingredient.displayUnit'),
      defaultStatus: StockStatus.fromWire(
        _asString(row['defaultStatus'], 'ingredient.defaultStatus'),
      ),
      spriteKey: _asString(row['spriteKey'], 'ingredient.spriteKey'),
    );
  }

  static List<Equipment> _parseEquipment(Object? payload) {
    final root = _asObject(payload, 'equipment.json');
    final rows = _asList(root['equipment'], 'equipment.json.equipment');
    return [
      for (final row in rows)
        _parseEquipmentRow(_asObject(row, 'equipment.json.equipment[]')),
    ];
  }

  static Equipment _parseEquipmentRow(Map<String, Object?> row) {
    return Equipment(
      code: _asString(row['id'], 'equipment.id'),
      name: _asString(row['name'], 'equipment.name'),
      description: _asString(row['description'], 'equipment.description'),
      shipped: row['shipped'] == true,
      pickerNote: _asOptionalString(row['pickerNote']),
      spriteKey: _asString(row['spriteKey'], 'equipment.spriteKey'),
    );
  }

  static Kitchen _parseKitchen(Map<String, Object?> payload) {
    final kitchen = _asObject(payload['kitchen'], 'kitchen_demo.json.kitchen');
    return Kitchen(
      uid: 'demo-kitchen',
      name: _asString(kitchen['name'], 'kitchen.name'),
    );
  }

  static Set<String> _parseOwnedEquipment(
    Map<String, Object?> payload,
    Map<String, Equipment> equipmentByCode,
  ) {
    final kitchen = _asObject(payload['kitchen'], 'kitchen_demo.json.kitchen');
    final codes = _asList(kitchen['equipment'], 'kitchen.equipment');
    final owned = <String>{};
    for (final code in codes) {
      final value = _asString(code, 'kitchen.equipment[]');
      if (!equipmentByCode.containsKey(value)) {
        throw FormatException(
          'kitchen owns unknown appliance "$value" (not in equipment.json)',
        );
      }
      owned.add(value);
    }
    return owned;
  }

  static Map<String, StockStatus> _parseStatuses(
    Map<String, Object?> payload,
    Map<String, Ingredient> ingredientsByCode,
  ) {
    final rows = _asList(payload['stock'], 'kitchen_demo.json.stock');
    final statuses = <String, StockStatus>{
      for (final ingredient in ingredientsByCode.values)
        ingredient.code: StockStatus.unknown,
    };
    for (final row in rows) {
      final entry = _asObject(row, 'kitchen_demo.json.stock[]');
      final code = _asString(entry['ingredient'], 'stock.ingredient');
      if (!ingredientsByCode.containsKey(code)) {
        throw FormatException(
          'stock row references unknown ingredient "$code"',
        );
      }
      statuses[code] = StockStatus.fromWire(
        _asString(entry['status'], 'stock.status'),
      );
    }
    return statuses;
  }

  static RecipeDetail _parseRecipe(
    Object? payload, {
    required Map<String, Ingredient> ingredientsByCode,
    required Map<String, Equipment> equipmentByCode,
  }) {
    final root = _asObject(payload, 'recipe file');
    _readSeedVersion(root, 'recipe file');
    final recipe = _asObject(root['recipe'], 'recipe file.recipe');

    final slug = _asString(recipe['slug'], 'recipe.slug');
    final requiredEquipment = <String>[
      for (final code in _asList(
        recipe['requiredEquipment'],
        'recipe.requiredEquipment',
      ))
        _asString(code, 'recipe.requiredEquipment[]'),
    ];
    for (final code in requiredEquipment) {
      if (!equipmentByCode.containsKey(code)) {
        throw FormatException('$slug requires unknown appliance "$code"');
      }
    }

    final methods = <RecipeMethod>[
      for (final row in _asList(recipe['methods'], 'recipe.methods'))
        _parseMethod(
          _asObject(row, 'recipe.methods[]'),
          slug: slug,
          equipmentByCode: equipmentByCode,
        ),
    ];

    final lines = <RecipeLine>[
      for (final row in _asList(recipe['ingredients'], 'recipe.ingredients'))
        _parseLine(
          _asObject(row, 'recipe.ingredients[]'),
          slug: slug,
          ingredientsByCode: ingredientsByCode,
        ),
    ];

    final steps = <RecipeStep>[
      for (final row in _asList(recipe['steps'], 'recipe.steps'))
        _parseStep(
          _asObject(row, 'recipe.steps[]'),
          slug: slug,
          equipmentByCode: equipmentByCode,
        ),
    ];

    if (steps.isEmpty) {
      throw FormatException('$slug has no steps');
    }

    return RecipeDetail(
      slug: slug,
      name: _asString(recipe['name'], 'recipe.name'),
      description: _asString(recipe['description'], 'recipe.description'),
      cuisine: _asString(recipe['cuisine'], 'recipe.cuisine'),
      baseServings: _asInt(recipe['baseServings'], 'recipe.baseServings'),
      prepMinutes: _asInt(recipe['prepMinutes'], 'recipe.prepMinutes'),
      cookMinutes: _asInt(recipe['cookMinutes'], 'recipe.cookMinutes'),
      difficulty: _asString(recipe['difficulty'], 'recipe.difficulty'),
      sortOrder: _asInt(recipe['sortOrder'], 'recipe.sortOrder'),
      dishStampKey: _asString(recipe['dishStampKey'], 'recipe.dishStampKey'),
      requiredEquipmentCodes: List.unmodifiable(requiredEquipment),
      methods: List.unmodifiable(methods),
      lines: List.unmodifiable(lines),
      steps: List.unmodifiable(steps),
    );
  }

  static RecipeMethod _parseMethod(
    Map<String, Object?> row, {
    required String slug,
    required Map<String, Equipment> equipmentByCode,
  }) {
    final equipmentCode = _asString(row['equipment'], 'method.equipment');
    if (!equipmentByCode.containsKey(equipmentCode)) {
      throw FormatException(
        '$slug method "${row['key']}" needs unknown appliance '
        '"$equipmentCode"',
      );
    }
    return RecipeMethod(
      key: _asString(row['key'], 'method.key'),
      label: _asString(row['label'], 'method.label'),
      equipmentCode: equipmentCode,
      iconKey: _asString(row['iconKey'], 'method.iconKey'),
      isCanonical: row['canonical'] == true,
    );
  }

  static RecipeLine _parseLine(
    Map<String, Object?> row, {
    required String slug,
    required Map<String, Ingredient> ingredientsByCode,
  }) {
    final code = _asString(row['ingredient'], 'ingredient.ingredient');
    final ingredient = ingredientsByCode[code];
    if (ingredient == null) {
      throw FormatException('$slug ingredient line uses unknown "$code"');
    }
    return RecipeLine(
      ingredientCode: code,
      name: ingredient.name,
      quantity: _asNum(row['quantity'], 'ingredient.quantity'),
      unitCode: _asString(row['unit'], 'ingredient.unit'),
      isOptional: row['optional'] == true,
      preparationNote: _asOptionalString(row['preparationNote']),
    );
  }

  static RecipeStep _parseStep(
    Map<String, Object?> row, {
    required String slug,
    required Map<String, Equipment> equipmentByCode,
  }) {
    final stepNumber = _asInt(row['stepNumber'], 'step.stepNumber');
    final equipmentCode = _asOptionalString(row['equipment']);
    if (equipmentCode != null && !equipmentByCode.containsKey(equipmentCode)) {
      throw FormatException(
        '$slug step $stepNumber uses unknown appliance "$equipmentCode"',
      );
    }
    final variants = <StepVariant>[
      for (final raw in _asList(row['variants'], 'step.variants'))
        _parseVariant(
          _asObject(raw, 'step.variants[]'),
          slug: slug,
          stepNumber: stepNumber,
          equipmentByCode: equipmentByCode,
        ),
    ];
    final duration = row['durationSeconds'];
    return RecipeStep(
      stepNumber: stepNumber,
      kind: StepKind.fromWire(_asString(row['kind'], 'step.kind')),
      instruction: _asString(row['instruction'], 'step.instruction'),
      detail: _asOptionalString(row['detail']),
      durationSeconds: duration == null
          ? null
          : _asInt(duration, 'step.durationSeconds'),
      equipmentCode: equipmentCode,
      ingredientRefs: List.unmodifiable([
        for (final code in _asList(
          row['ingredientRefs'],
          'step.ingredientRefs',
        ))
          _asString(code, 'step.ingredientRefs[]'),
      ]),
      caution: _asOptionalString(row['caution']),
      spriteKey: _asString(row['spriteKey'], 'step.spriteKey'),
      variantGroup: _asOptionalString(row['variantGroup']),
      variants: List.unmodifiable(variants),
    );
  }

  static StepVariant _parseVariant(
    Map<String, Object?> row, {
    required String slug,
    required int stepNumber,
    required Map<String, Equipment> equipmentByCode,
  }) {
    final equipmentCode = _asString(row['equipment'], 'variant.equipment');
    if (!equipmentByCode.containsKey(equipmentCode)) {
      throw FormatException(
        '$slug step $stepNumber variant needs unknown appliance '
        '"$equipmentCode"',
      );
    }
    final duration = row['durationSeconds'];
    return StepVariant(
      methodKey: _asString(row['method'], 'variant.method'),
      equipmentCode: equipmentCode,
      instruction: _asOptionalString(row['instruction']),
      durationSeconds: duration == null
          ? null
          : _asInt(duration, 'variant.durationSeconds'),
      spriteKey: _asOptionalString(row['spriteKey']),
      priority: row['priority'] == null
          ? 0
          : _asInt(row['priority'], 'variant.priority'),
    );
  }
}
