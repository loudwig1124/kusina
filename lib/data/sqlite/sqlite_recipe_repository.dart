/// Recipe repository on SQLite (`docs/08` §4, §5.2): hand-written SQL, no ORM.
///
/// The frozen schema stores recipes, display ingredient lines, steps and step
/// variants; the cook-method list is derived from each `variant_group`'s
/// canonical appliance plus its variant rows, so no methods table is needed.
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/models/recipe.dart';
import '../repositories/recipe_repository.dart';
import 'mappers.dart';

class SqliteRecipeRepository implements RecipeRepository {
  const SqliteRecipeRepository(this._db);

  final Database _db;

  @override
  Future<List<RecipeDetail>> listRecipes() async {
    final rows = await _db.query('recipes', orderBy: 'id ASC');
    return <RecipeDetail>[for (final row in rows) await _build(row)];
  }

  @override
  Future<RecipeDetail?> findBySlug(String slug) async {
    final rows = await _db.query(
      'recipes',
      where: 'slug = ?',
      whereArgs: <Object?>[slug],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _build(rows.single);
  }

  Future<RecipeDetail> _build(Map<String, Object?> row) async {
    final recipeId = row['id']! as int;
    final equipment = await _equipmentLookups();
    final lines = await _lines(recipeId);
    final steps = await _steps(recipeId, equipment.codeById);
    final groupSteps = steps
        .where((step) => step.variantGroup != null)
        .map(
          (step) => <String, Object?>{
            'equipment_id': equipment.idByCode[step.equipmentCode],
            'variants': <Map<String, Object?>>[
              for (final variant in step.variants)
                <String, Object?>{
                  'equipment_id': equipment.idByCode[variant.equipmentCode],
                },
            ],
          },
        )
        .toList(growable: false);
    final methods = recipeMethodsFromRows(
      groupSteps: groupSteps,
      equipmentCodeById: equipment.codeById,
      equipmentNameById: equipment.nameById,
    );
    final requiredEquipment = await _requiredEquipment(recipeId);

    return RecipeDetail(
      slug: row['slug']! as String,
      name: row['name']! as String,
      description: (row['description'] as String?) ?? '',
      cuisine: row['cuisine']! as String,
      baseServings: row['servings']! as int,
      prepMinutes: (row['prep_minutes'] as int?) ?? 0,
      cookMinutes: (row['cook_minutes'] as int?) ?? 0,
      difficulty: row['difficulty']! as String,
      // The frozen schema has no sort_order column; the seeded ids are the
      // content's sort order (1 Adobo, 2 Sinangag, 3 Crispy Pork Belly).
      sortOrder: recipeId,
      dishStampKey: dishStampKeyFor(row['slug']! as String),
      requiredEquipmentCodes: requiredEquipment,
      methods: methods,
      lines: lines,
      steps: steps,
    );
  }

  Future<
    ({
      Map<int, String> codeById,
      Map<int, String> nameById,
      Map<String, int> idByCode,
    })
  >
  _equipmentLookups() async {
    final rows = await _db.query(
      'equipment',
      columns: <String>['id', 'code', 'name'],
    );
    final codeById = <int, String>{};
    final nameById = <int, String>{};
    final idByCode = <String, int>{};
    for (final row in rows) {
      final id = row['id']! as int;
      codeById[id] = row['code']! as String;
      nameById[id] = row['name']! as String;
      idByCode[row['code']! as String] = id;
    }
    return (codeById: codeById, nameById: nameById, idByCode: idByCode);
  }

  Future<List<String>> _requiredEquipment(int recipeId) async {
    final rows = await _db.rawQuery(
      'SELECT e.code AS code FROM recipe_equipment re '
      'JOIN equipment e ON e.id = re.equipment_id '
      'WHERE re.recipe_id = ? ORDER BY e.id',
      <Object?>[recipeId],
    );
    return List<String>.unmodifiable(rows.map((row) => row['code']! as String));
  }

  Future<List<RecipeLine>> _lines(int recipeId) async {
    final rows = await _db.rawQuery(
      'SELECT ri.quantity AS quantity, ri.is_optional AS is_optional, '
      '  ri.preparation_note AS preparation_note, '
      '  i.code AS ingredient_code, i.name AS ingredient_name, '
      '  u.code AS unit_code '
      'FROM recipe_ingredients ri '
      'JOIN ingredients i ON i.id = ri.ingredient_id '
      'JOIN units u ON u.id = ri.unit_id '
      'WHERE ri.recipe_id = ? ORDER BY ri.rowid',
      <Object?>[recipeId],
    );
    return List<RecipeLine>.unmodifiable(rows.map(recipeLineFromRow));
  }

  Future<List<RecipeStep>> _steps(
    int recipeId,
    Map<int, String> equipmentCodeById,
  ) async {
    final rows = await _db.rawQuery(
      'SELECT * FROM recipe_steps WHERE recipe_id = ? ORDER BY step_number',
      <Object?>[recipeId],
    );
    final variantRows = await _db.rawQuery(
      'SELECT v.* FROM recipe_step_variants v '
      'JOIN recipe_steps s ON s.id = v.step_id '
      'WHERE s.recipe_id = ? ORDER BY v.priority DESC, v.id',
      <Object?>[recipeId],
    );
    final variantsByStep = <int, List<Map<String, Object?>>>{};
    for (final variant in variantRows) {
      variantsByStep
          .putIfAbsent(
            variant['step_id']! as int,
            () => <Map<String, Object?>>[],
          )
          .add(variant);
    }

    return List<RecipeStep>.unmodifiable(<RecipeStep>[
      for (final row in rows)
        _stepFromRow(row, variantsByStep, equipmentCodeById),
    ]);
  }

  RecipeStep _stepFromRow(
    Map<String, Object?> row,
    Map<int, List<Map<String, Object?>>> variantsByStep,
    Map<int, String> equipmentCodeById,
  ) {
    final stepId = row['id']! as int;
    final equipmentId = row['equipment_id'] as int?;
    return RecipeStep(
      stepNumber: row['step_number']! as int,
      kind: StepKind.fromWire(row['kind']! as String),
      instruction: row['instruction']! as String,
      detail: row['detail'] as String?,
      durationSeconds: row['duration_seconds'] as int?,
      equipmentCode: equipmentId == null
          ? null
          : equipmentCodeById[equipmentId],
      ingredientRefs: decodeStringArray(row['ingredient_refs_json']),
      caution: row['caution'] as String?,
      spriteKey: row['sprite_key']! as String,
      variantGroup: row['variant_group'] as String?,
      variants: List<StepVariant>.unmodifiable(<StepVariant>[
        for (final variant in variantsByStep[stepId] ?? const [])
          _variantFromRow(variant, equipmentCodeById),
      ]),
    );
  }

  StepVariant _variantFromRow(
    Map<String, Object?> row,
    Map<int, String> equipmentCodeById,
  ) {
    final equipmentCode = equipmentCodeById[row['equipment_id']! as int]!;
    final naming = CookMethod.forEquipment(equipmentCode);
    return StepVariant(
      methodKey: naming.key,
      equipmentCode: equipmentCode,
      instruction: row['instruction_override'] as String?,
      durationSeconds: row['duration_override'] as int?,
      spriteKey: row['sprite_override'] as String?,
      priority: row['priority']! as int,
    );
  }
}
