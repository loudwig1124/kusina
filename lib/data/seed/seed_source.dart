/// Seed content loader (`docs/08` §4.10): the t4 `assets/seed/*.json` arrays,
/// one file per table, keyed by table name.
///
/// The files are the row shapes of `db/schema-sqlite.sql` (the content author's
/// validator proves it); this loader only decodes them. Tests inject the same
/// JSON from disk, the app reads the bundled assets.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// Row lists for the 11 seeded tables, in foreign-key-safe insert order.
class SeedDataSet {
  const SeedDataSet({
    required this.units,
    required this.ingredients,
    required this.equipment,
    required this.kitchens,
    required this.kitchenEquipment,
    required this.stockStatus,
    required this.recipes,
    required this.recipeEquipment,
    required this.recipeIngredients,
    required this.recipeSteps,
    required this.recipeStepVariants,
  });

  final List<Map<String, Object?>> units;
  final List<Map<String, Object?>> ingredients;
  final List<Map<String, Object?>> equipment;
  final List<Map<String, Object?>> kitchens;
  final List<Map<String, Object?>> kitchenEquipment;
  final List<Map<String, Object?>> stockStatus;
  final List<Map<String, Object?>> recipes;
  final List<Map<String, Object?>> recipeEquipment;
  final List<Map<String, Object?>> recipeIngredients;
  final List<Map<String, Object?>> recipeSteps;
  final List<Map<String, Object?>> recipeStepVariants;

  /// Insert order: parents before children.
  List<({String table, List<Map<String, Object?>> rows})> get tables =>
      <({String table, List<Map<String, Object?>> rows})>[
        (table: 'units', rows: units),
        (table: 'ingredients', rows: ingredients),
        (table: 'equipment', rows: equipment),
        (table: 'kitchens', rows: kitchens),
        (table: 'kitchen_equipment', rows: kitchenEquipment),
        (table: 'stock_status', rows: stockStatus),
        (table: 'recipes', rows: recipes),
        (table: 'recipe_equipment', rows: recipeEquipment),
        (table: 'recipe_ingredients', rows: recipeIngredients),
        (table: 'recipe_steps', rows: recipeSteps),
        (table: 'recipe_step_variants', rows: recipeStepVariants),
      ];

  List<Map<String, Object?>> rowsFor(String table) {
    for (final entry in tables) {
      if (entry.table == table) {
        return entry.rows;
      }
    }
    return const <Map<String, Object?>>[];
  }
}

abstract interface class SeedSource {
  Future<SeedDataSet> load();
}

/// Reads the bundled `assets/seed/` JSON files.
class AssetSeedSource implements SeedSource {
  const AssetSeedSource();

  static const String _root = 'assets/seed/';

  @override
  Future<SeedDataSet> load() async {
    final files = <String, String>{};
    for (final name in seedFileNames) {
      files[name] = await rootBundle.loadString('$_root$name');
    }
    return parseSeedFiles(files);
  }
}

/// The eleven seed files and the table each one feeds.
const Map<String, String> seedFileTables = <String, String>{
  'units.json': 'units',
  'ingredients.json': 'ingredients',
  'equipment.json': 'equipment',
  'kitchens.json': 'kitchens',
  'kitchen_equipment.json': 'kitchen_equipment',
  'stock_status.json': 'stock_status',
  'recipes.json': 'recipes',
  'recipe_equipment.json': 'recipe_equipment',
  'recipe_ingredients.json': 'recipe_ingredients',
  'recipe_steps.json': 'recipe_steps',
  'recipe_step_variants.json': 'recipe_step_variants',
};

Iterable<String> get seedFileNames => seedFileTables.keys;

/// Parses `file name -> JSON text` into the seed data set.
SeedDataSet parseSeedFiles(Map<String, String> files) {
  Map<String, Object?> table(String fileName) {
    final text = files[fileName];
    if (text == null) {
      throw FormatException('missing seed file $fileName');
    }
    final rows = _decodeList(text, fileName);
    return <String, Object?>{'rows': rows};
  }

  List<Map<String, Object?>> rowsOf(String fileName) =>
      (table(fileName)['rows']! as List<Map<String, Object?>>);

  return SeedDataSet(
    units: rowsOf('units.json'),
    ingredients: rowsOf('ingredients.json'),
    equipment: rowsOf('equipment.json'),
    kitchens: rowsOf('kitchens.json'),
    kitchenEquipment: rowsOf('kitchen_equipment.json'),
    stockStatus: rowsOf('stock_status.json'),
    recipes: rowsOf('recipes.json'),
    recipeEquipment: rowsOf('recipe_equipment.json'),
    recipeIngredients: rowsOf('recipe_ingredients.json'),
    recipeSteps: rowsOf('recipe_steps.json'),
    recipeStepVariants: rowsOf('recipe_step_variants.json'),
  );
}

List<Map<String, Object?>> _decodeList(String text, String label) {
  final dynamic decoded = jsonDecode(text);
  if (decoded is! List<Object?>) {
    throw FormatException('$label must be a JSON array');
  }
  return <Map<String, Object?>>[
    for (final row in decoded)
      if (row is Map<String, Object?>)
        row
      else
        throw FormatException('$label rows must be JSON objects'),
  ];
}
