/// Filipino gloss lookup for the SQLite layer.
///
/// The frozen schema has no gloss column, and the content validator requires the
/// seed rows to carry exactly the DDL columns, so the glosses come from the
/// bundled fixture catalog (`assets/fixtures/ingredients.json`) instead of a
/// duplicated seed field. One asset read, one map, both repository paths render
/// the same "Garlic (Bawang)" row.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// Asset key of the fixture catalog that carries the glosses.
const String ingredientCatalogAssetKey = 'assets/fixtures/ingredients.json';

typedef GlossLoader = Future<Map<String, String>> Function();

/// Loads the glosses from the bundled fixture catalog.
Future<Map<String, String>> loadIngredientGlossesFromAsset() async {
  final text = await rootBundle.loadString(ingredientCatalogAssetKey);
  return parseIngredientGlosses(text);
}

/// Parses `code -> filipinoGloss` from the fixture catalog JSON.
Map<String, String> parseIngredientGlosses(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('ingredients.json must be a JSON object');
  }
  final rows = decoded['ingredients'];
  if (rows is! List<Object?>) {
    throw const FormatException('ingredients.json.ingredients must be a list');
  }
  final glosses = <String, String>{};
  for (final row in rows) {
    if (row is! Map<String, Object?>) {
      continue;
    }
    final code = row['id'];
    final gloss = row['filipinoGloss'];
    if (code is String && gloss is String && gloss.isNotEmpty) {
      glosses[code] = gloss;
    }
  }
  return Map<String, String>.unmodifiable(glosses);
}
