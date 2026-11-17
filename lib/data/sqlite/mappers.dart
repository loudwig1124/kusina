/// Row <-> model mapping for the SQLite layer (`docs/08` §4, §5.1).
///
/// Integer surrogate keys never leak: lookups convert them to the stable codes
/// the domain uses. The only content-shaped derivation is the cook-method name
/// for an appliance, because the schema stores methods as variant rows (there
/// is no methods table, and the schema is frozen).
library;

import '../../domain/models/recipe.dart';

/// Cook-method identity for an appliance.
///
/// The method *offered* by a dish comes from the database (`variant_group` steps
/// and their variant rows); only the method's presentation name is mapped here
/// so the frozen schema needs no extra table. Unknown appliances fall back to
/// their own code/name, so a future dish still works.
class CookMethod {
  const CookMethod({
    required this.key,
    required this.label,
    required this.iconKey,
  });

  final String key;
  final String label;
  final String iconKey;

  static const Map<String, CookMethod> _byEquipmentCode = <String, CookMethod>{
    'stovetop': CookMethod(
      key: 'pan_fry',
      label: 'Pan-fry',
      iconKey: 'variant_panfry',
    ),
    'air_fryer': CookMethod(
      key: 'air_fry',
      label: 'Air-fry',
      iconKey: 'variant_airfry',
    ),
    'oven': CookMethod(
      key: 'oven_bake',
      label: 'Bake',
      iconKey: 'variant_oven',
    ),
    'grill': CookMethod(key: 'grill', label: 'Grill', iconKey: 'variant_grill'),
    'pressure_cooker': CookMethod(
      key: 'pressure_cook',
      label: 'Pressure-cook',
      iconKey: 'variant_pressure',
    ),
  };

  static CookMethod forEquipment(String code, {String? name}) {
    return _byEquipmentCode[code] ??
        CookMethod(
          key: code,
          label: name ?? code,
          iconKey: 'variant_${code.replaceAll('_', '')}',
        );
  }
}

/// The dish stamp key for a slug (`chicken-adobo` -> `dish_chicken_adobo`).
/// The frozen schema has no stamp column; the sprite key is structural.
String dishStampKeyFor(String slug) => 'dish_${slug.replaceAll('-', '_')}';

/// Decodes a JSON array of strings (e.g. `ingredient_refs_json`).
List<String> decodeStringArray(Object? value) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! String || value.trim().isEmpty) {
    return const <String>[];
  }
  final trimmed = value.trim();
  if (!trimmed.startsWith('[')) {
    return const <String>[];
  }
  return <String>[
    for (final part in trimmed.substring(1, trimmed.length - 1).split(','))
      if (part.trim().isNotEmpty) part.trim().replaceAll('"', ''),
  ];
}

/// Encodes a list of stable code strings for the session snapshot.
String encodeStringArray(List<String> values) {
  return '[${values.map((value) => '"$value"').join(',')}]';
}

/// `RecipeLine` from a joined `recipe_ingredients` row.
RecipeLine recipeLineFromRow(Map<String, Object?> row) {
  return RecipeLine(
    ingredientCode: row['ingredient_code']! as String,
    name: row['ingredient_name']! as String,
    quantity: row['quantity']! as num,
    unitCode: row['unit_code']! as String,
    isOptional: (row['is_optional']! as int) == 1,
    preparationNote: row['preparation_note'] as String?,
  );
}

/// `RecipeMethod` list for a dish, derived from its variant-group rows.
///
/// A method exists for each appliance the group offers: the canonical step's
/// appliance and every variant's appliance. The method that owns the canonical
/// rows is flagged `isCanonical`; nothing here chooses a method for the cook.
List<RecipeMethod> recipeMethodsFromRows({
  required List<Map<String, Object?>> groupSteps,
  required Map<int, String> equipmentCodeById,
  required Map<int, String> equipmentNameById,
}) {
  // equipment id -> does it own the canonical rows?
  final canonicalByEquipment = <int, bool>{};
  for (final step in groupSteps) {
    final canonicalEquipment = step['equipment_id'] as int?;
    if (canonicalEquipment != null) {
      canonicalByEquipment.putIfAbsent(canonicalEquipment, () => true);
    }
    for (final variant in (step['variants'] as List<Object?>?) ?? const []) {
      final row = variant! as Map<String, Object?>;
      canonicalByEquipment.putIfAbsent(
        row['equipment_id']! as int,
        () => false,
      );
    }
  }
  // Deterministic order: the catalog's equipment order (the seeded ids), which
  // is the content's declared method order.
  final equipmentIds = canonicalByEquipment.keys.toList()..sort();
  return List<RecipeMethod>.unmodifiable(<RecipeMethod>[
    for (final equipmentId in equipmentIds)
      if (equipmentCodeById[equipmentId] case final code?)
        RecipeMethod(
          key: CookMethod.forEquipment(
            code,
            name: equipmentNameById[equipmentId],
          ).key,
          label: CookMethod.forEquipment(
            code,
            name: equipmentNameById[equipmentId],
          ).label,
          equipmentCode: code,
          iconKey: CookMethod.forEquipment(
            code,
            name: equipmentNameById[equipmentId],
          ).iconKey,
          isCanonical: canonicalByEquipment[equipmentId] ?? false,
        ),
  ]);
}
