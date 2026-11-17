/// The guide store on SQLite (`docs/09` §11.4, §8.5): sessions, the pinned
/// `session_step_choices` path, the absolute timer fields and the completion
/// transaction. Also implements the read-side [SessionRepository].
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/guide/guide_models.dart';
import '../../domain/guide/guide_rules.dart';
import '../../domain/guide/guide_store.dart';
import '../../domain/models/recipe.dart';
import '../../domain/models/stock.dart';
import '../repositories/session_repository.dart';
import 'app_database.dart';
import 'mappers.dart';
import 'sqlite_equipment_repository.dart';
import 'sqlite_recipe_repository.dart';
import 'sqlite_stock_repository.dart';

class SqliteGuideStore implements GuideStore, SessionRepository {
  SqliteGuideStore(
    this._db, {
    SqliteRecipeRepository? recipes,
    SqliteStockRepository? stock,
    SqliteEquipmentRepository? equipment,
    Map<String, String> ingredientGlosses = const <String, String>{},
    DateTime Function()? clock,
  }) : _recipes = recipes ?? SqliteRecipeRepository(_db),
       _stock =
           stock ??
           SqliteStockRepository(
             _db,
             clock: clock,
             ingredientGlosses: ingredientGlosses,
           ),
       _equipment = equipment ?? SqliteEquipmentRepository(_db, clock: clock),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final Database _db;
  final SqliteRecipeRepository _recipes;
  final SqliteStockRepository _stock;
  final SqliteEquipmentRepository _equipment;
  final DateTime Function() _clock;

  static const int _kitchenId = 1;

  // ---------------------------------------------------------------------------
  // Recipe + presence reads
  // ---------------------------------------------------------------------------

  @override
  Future<RecipeDetail?> loadRecipe(String slug) => _recipes.findBySlug(slug);

  @override
  Future<Map<String, StockStatus>> statusesOf(List<String> ingredientCodes) =>
      _stock.getStatuses(ingredientCodes);

  @override
  Future<Set<String>> ownedEquipmentCodes() => _equipment.ownedIds();

  // ---------------------------------------------------------------------------
  // Session reads
  // ---------------------------------------------------------------------------

  @override
  Future<GuidedSession?> loadActiveSession() async {
    final rows = await _db.query(
      'cooking_sessions',
      columns: <String>['id'],
      where: 'status = ?',
      whereArgs: <Object?>['in_progress'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _loadSession('${rows.single['id']}');
  }

  @override
  Future<GuidedSession?> loadSession(String sessionId) =>
      _loadSession(sessionId);

  @override
  Future<List<GuidedSession>> history({int limit = 50, int offset = 0}) async {
    final rows = await _db.query(
      'cooking_sessions',
      columns: <String>['id'],
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    final sessions = <GuidedSession>[];
    for (final row in rows) {
      final session = await _loadSession('${row['id']}');
      if (session != null) {
        sessions.add(session);
      }
    }
    return List<GuidedSession>.unmodifiable(sessions);
  }

  /// All sessions (guide-store view of [history]).
  @override
  Future<List<GuidedSession>> sessions() => history(limit: 200);

  Future<GuidedSession?> _loadSession(String sessionId) async {
    final id = int.tryParse(sessionId);
    if (id == null) {
      return null;
    }
    final rows = await _db.rawQuery(
      'SELECT s.*, r.slug AS recipe_slug, r.name AS recipe_name, '
      '  k.kitchen_uid AS kitchen_uid, '
      '  (SELECT COUNT(*) FROM recipe_steps rs '
      '   WHERE rs.recipe_id = s.recipe_id) AS total_steps '
      'FROM cooking_sessions s '
      'JOIN recipes r ON r.id = s.recipe_id '
      'JOIN kitchens k ON k.id = s.kitchen_id '
      'WHERE s.id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    return GuidedSession(
      id: '$id',
      kitchenId: row['kitchen_uid']! as String,
      recipeSlug: row['recipe_slug']! as String,
      recipeName: row['recipe_name']! as String,
      status: _statusFromWire(row['status']! as String),
      currentStepNumber: row['current_step_number']! as int,
      totalSteps: row['total_steps']! as int,
      startedAtUtc: parseUtc(row['started_at']! as String),
      lastSeenAtUtc: _parseNullable(row['last_seen_at']),
      completedAtUtc: _parseNullable(row['completed_at']),
      timerStartedAtUtc: _parseNullable(row['timer_started_at']),
      timerDurationSeconds: row['timer_duration_seconds'] as int?,
      startedWithoutAvailability:
          (row['started_without_availability']! as int) == 1,
      missingCodes: decodeStringArray(row['missing_requirements_json']),
      path: await _loadPath(id),
    );
  }

  /// Rebuilds the pinned path from `session_step_choices`: the recipe supplies
  /// the canonical row, the pinned variant supplies the deltas.
  Future<EquipmentPath> _loadPath(int sessionId) async {
    final rows = await _db.rawQuery(
      'SELECT c.step_number AS step_number, c.is_variant AS is_variant, '
      '  s.kind AS kind, s.instruction AS instruction, s.detail AS detail, '
      '  s.duration_seconds AS duration_seconds, '
      '  s.ingredient_refs_json AS ingredient_refs_json, '
      '  s.caution AS caution, s.sprite_key AS sprite_key, '
      '  s.variant_group AS variant_group, '
      '  v.instruction_override AS instruction_override, '
      '  v.duration_override AS duration_override, '
      '  v.sprite_override AS sprite_override, '
      '  ce.code AS choice_equipment_code, se.code AS step_equipment_code, '
      '  ve.code AS variant_equipment_code '
      'FROM session_step_choices c '
      'JOIN recipe_steps s ON s.step_number = c.step_number '
      '  AND s.recipe_id = (SELECT recipe_id FROM cooking_sessions '
      '                     WHERE id = c.session_id) '
      'LEFT JOIN recipe_step_variants v ON v.id = c.variant_id '
      'LEFT JOIN equipment ce ON ce.id = c.equipment_id '
      'LEFT JOIN equipment se ON se.id = s.equipment_id '
      'LEFT JOIN equipment ve ON ve.id = v.equipment_id '
      'WHERE c.session_id = ? ORDER BY c.step_number',
      <Object?>[sessionId],
    );

    String? methodKey;
    final steps = <int, PinnedStep>{};
    for (final row in rows) {
      final stepNumber = row['step_number']! as int;
      final isVariant = (row['is_variant']! as int) == 1;
      final equipmentCode =
          (row['choice_equipment_code'] as String?) ??
          (row['step_equipment_code'] as String?);
      if (methodKey == null &&
          row['variant_group'] != null &&
          equipmentCode != null) {
        methodKey = CookMethod.forEquipment(equipmentCode).key;
      }
      final variantEquipment = row['variant_equipment_code'] as String?;
      final instruction = isVariant
          ? (row['instruction_override'] as String? ??
                row['instruction']! as String)
          : row['instruction']! as String;
      final duration = isVariant
          ? (row['duration_override'] as int? ??
                row['duration_seconds'] as int?)
          : row['duration_seconds'] as int?;
      final spriteKey = isVariant
          ? (row['sprite_override'] as String? ?? row['sprite_key']! as String)
          : row['sprite_key']! as String;
      steps[stepNumber] = PinnedStep(
        stepNumber: stepNumber,
        equipmentCode: equipmentCode,
        variantMethodKey: isVariant && variantEquipment != null
            ? CookMethod.forEquipment(variantEquipment).key
            : null,
        isVariant: isVariant,
        snapshot: StepSnapshot(
          instruction: instruction,
          detail: row['detail'] as String?,
          durationSeconds: duration,
          spriteKey: spriteKey,
          equipmentCode: equipmentCode,
          isVariant: isVariant,
          variantMethodKey: isVariant && variantEquipment != null
              ? CookMethod.forEquipment(variantEquipment).key
              : null,
          kind: StepKind.fromWire(row['kind']! as String),
          ingredientCodes: decodeStringArray(row['ingredient_refs_json']),
          caution: row['caution'] as String?,
          variantGroup: row['variant_group'] as String?,
        ),
      );
    }
    return EquipmentPath(methodKey: methodKey, steps: steps);
  }

  // ---------------------------------------------------------------------------
  // Session writes
  // ---------------------------------------------------------------------------

  @override
  Future<GuidedSession> insertSession(GuidedSession session) async {
    final active = await loadActiveSession();
    if (active != null) {
      throw const EngineException(
        EngineError.activeSessionExists,
        'one in-progress session per kitchen',
      );
    }
    final sessionId = await _db.transaction<int>((txn) async {
      final recipeRows = await txn.query(
        'recipes',
        columns: <String>['id', 'servings'],
        where: 'slug = ?',
        whereArgs: <Object?>[session.recipeSlug],
        limit: 1,
      );
      if (recipeRows.isEmpty) {
        throw const EngineException(EngineError.recipeNotFound);
      }
      final recipeId = recipeRows.single['id']! as int;
      final now = isoUtc(_clock());
      final id = await txn.rawInsert(
        'INSERT INTO cooking_sessions (kitchen_id, recipe_id, servings, status, '
        '  current_step_number, started_at, updated_at, last_seen_at, '
        '  started_without_availability, missing_requirements_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          _kitchenId,
          recipeId,
          recipeRows.single['servings']! as int,
          'in_progress',
          1,
          isoUtc(session.startedAtUtc),
          now,
          isoUtc(session.lastSeenAtUtc ?? session.startedAtUtc),
          session.startedWithoutAvailability ? 1 : 0,
          session.startedWithoutAvailability
              ? encodeStringArray(session.missingCodes)
              : null,
        ],
      );
      final pinned = session.path.steps.values.toList()
        ..sort((a, b) => a.stepNumber.compareTo(b.stepNumber));
      for (final step in pinned) {
        final stepRows = await txn.query(
          'recipe_steps',
          columns: <String>['id'],
          where: 'recipe_id = ? AND step_number = ?',
          whereArgs: <Object?>[recipeId, step.stepNumber],
          limit: 1,
        );
        if (stepRows.isEmpty) {
          throw EngineException(
            EngineError.seedMissing,
            'no recipe step ${step.stepNumber} in ${session.recipeSlug}',
          );
        }
        final stepId = stepRows.single['id']! as int;
        int? equipmentId;
        if (step.equipmentCode != null) {
          equipmentId = await _equipmentId(txn, step.equipmentCode!);
        }
        int? variantId;
        if (step.isVariant) {
          final variantRows = await txn.query(
            'recipe_step_variants',
            columns: <String>['id'],
            where: 'step_id = ? AND equipment_id = ?',
            whereArgs: <Object?>[stepId, equipmentId],
            limit: 1,
          );
          if (variantRows.isEmpty) {
            throw EngineException(
              EngineError.seedMissing,
              'no variant row for step ${step.stepNumber}',
            );
          }
          variantId = variantRows.single['id']! as int;
        }
        await txn.insert('session_step_choices', <String, Object?>{
          'session_id': id,
          'step_number': step.stepNumber,
          'equipment_id': equipmentId,
          'is_variant': step.isVariant ? 1 : 0,
          'variant_id': variantId,
        });
      }
      return id;
    });
    final stored = await _loadSession('$sessionId');
    if (stored == null) {
      throw const EngineException(EngineError.seedMissing);
    }
    return stored;
  }

  @override
  Future<void> updateStepNumber(
    String sessionId,
    int stepNumber,
    DateTime nowUtc,
  ) async {
    final id = _requireId(sessionId);
    final changed = await _db.rawUpdate(
      'UPDATE cooking_sessions SET current_step_number = ?, '
      '  timer_started_at = NULL, timer_duration_seconds = NULL, '
      '  last_seen_at = ?, updated_at = ? '
      'WHERE id = ? AND status = ?',
      <Object?>[stepNumber, isoUtc(nowUtc), isoUtc(nowUtc), id, 'in_progress'],
    );
    if (changed != 1) {
      throw const EngineException(EngineError.sessionNotActive);
    }
  }

  @override
  Future<void> writeTimer(
    String sessionId,
    DateTime? startedAtUtc,
    int? durationSeconds,
  ) async {
    final id = _requireId(sessionId);
    final changed = await _db.rawUpdate(
      'UPDATE cooking_sessions SET timer_started_at = ?, '
      '  timer_duration_seconds = ?, updated_at = ? '
      'WHERE id = ? AND status = ?',
      <Object?>[
        startedAtUtc == null ? null : isoUtc(startedAtUtc),
        durationSeconds,
        isoUtc(_clock()),
        id,
        'in_progress',
      ],
    );
    if (changed != 1) {
      throw const EngineException(EngineError.sessionNotActive);
    }
  }

  @override
  Future<void> writeLastSeen(String sessionId, DateTime atUtc) async {
    final id = _requireId(sessionId);
    await _db.rawUpdate(
      'UPDATE cooking_sessions SET last_seen_at = ?, updated_at = ? '
      'WHERE id = ? AND status = ?',
      <Object?>[isoUtc(atUtc), isoUtc(_clock()), id, 'in_progress'],
    );
  }

  @override
  Future<GuidedSession> abandonSession(
    String sessionId,
    DateTime nowUtc,
  ) async {
    final id = _requireId(sessionId);
    final changed = await _db.rawUpdate(
      'UPDATE cooking_sessions SET status = ?, completed_at = NULL, '
      '  timer_started_at = NULL, timer_duration_seconds = NULL, '
      '  last_seen_at = ?, updated_at = ? '
      'WHERE id = ? AND status = ?',
      <Object?>['abandoned', isoUtc(nowUtc), isoUtc(nowUtc), id, 'in_progress'],
    );
    if (changed != 1) {
      throw const EngineException(EngineError.sessionNotActive);
    }
    final stored = await _loadSession(sessionId);
    if (stored == null) {
      throw const EngineException(EngineError.seedMissing);
    }
    return stored;
  }

  @override
  Future<CompletionResult> completeAtomically({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  }) async {
    final id = _requireId(sessionId);
    try {
      return await _completeInTransaction(
        sessionId: id,
        lines: lines,
        nowUtc: nowUtc,
      );
    } on _CompletionAbort catch (abort) {
      // A guard failed after the first write: the transaction rolled back, so
      // report the rejection with zero events and the session untouched.
      return _rejected(lines, abort.error);
    } on DatabaseException {
      // Any SQL failure also rolled back; surface it as a rejected completion
      // instead of a half-written cook.
      return _rejected(lines, EngineError.seedMissing);
    }
  }

  Future<CompletionResult> _completeInTransaction({
    required int sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  }) {
    final id = sessionId;
    return _db.transaction<CompletionResult>((txn) async {
      // 1. Read the session inside the transaction.
      final sessionRows = await txn.query(
        'cooking_sessions',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (sessionRows.isEmpty) {
        return _rejected(lines, EngineError.seedMissing);
      }
      final row = sessionRows.single;
      final status = row['status']! as String;
      if (status == 'completed') {
        return CompletionResult(
          outcome: CompletionOutcome.alreadyCompleted,
          lines: lines,
          usedItCount: 0,
          usedItUpCount: 0,
          didntUseCount: lines.length,
          restockCorrections: 0,
          eventsWritten: 0,
        );
      }
      if (status != 'in_progress') {
        return _rejected(lines, EngineError.sessionNotActive);
      }
      final recipeId = row['recipe_id']! as int;
      final totalSteps = await _totalSteps(txn, recipeId);
      if ((row['current_step_number']! as int) != totalSteps + 1) {
        return _rejected(lines, EngineError.completionIncomplete);
      }

      // 2. Re-read the statuses inside the transaction; the review snapshot is
      //    never trusted for the write (docs/09 §8.5 step 2).
      final current = <String, StockStatus>{};
      final ingredientIds = <String, int>{};
      for (final line in lines) {
        final rows = await txn.rawQuery(
          'SELECT i.id AS id, s.status AS status FROM ingredients i '
          'JOIN stock_status s ON s.ingredient_id = i.id AND s.kitchen_id = ? '
          'WHERE i.code = ? LIMIT 1',
          <Object?>[_kitchenId, line.ingredientCode],
        );
        if (rows.isEmpty) {
          return _rejected(lines, EngineError.seedMissing);
        }
        ingredientIds[line.ingredientCode] = rows.single['id']! as int;
        current[line.ingredientCode] = StockStatus.fromWire(
          rows.single['status']! as String,
        );
      }

      // 3. Validate every line before the first write.
      for (final line in lines) {
        final recipeLines = await txn.query(
          'recipe_ingredients',
          columns: <String>['ingredient_id'],
          where: 'recipe_id = ? AND ingredient_id = ?',
          whereArgs: <Object?>[recipeId, ingredientIds[line.ingredientCode]],
          limit: 1,
        );
        if (recipeLines.isEmpty) {
          return _rejected(lines, EngineError.invalidCompletionLine);
        }
        final live = current[line.ingredientCode]!;
        final effective = line.restockToHave && live != StockStatus.have
            ? StockStatus.have
            : live;
        if (!isChoiceAllowed(effective, line.choice)) {
          return _rejected(lines, EngineError.invalidCompletionLine);
        }
      }

      // 4. Apply the transition chains (restock first, then the usage write).
      var restockCorrections = 0;
      var eventsWritten = 0;
      for (final line in lines) {
        final transitions = completionTransitionsFor(
          ingredientCode: line.ingredientCode,
          current: current[line.ingredientCode]!,
          choice: line.choice,
          restockToHave: line.restockToHave,
        );
        for (final transition in transitions) {
          final ingredientId = ingredientIds[transition.ingredientCode]!;
          final changed = await txn.rawUpdate(
            'UPDATE stock_status SET status = ?, updated_at = ? '
            'WHERE kitchen_id = ? AND ingredient_id = ? AND status = ?',
            <Object?>[
              transition.to.wireCode,
              isoUtc(nowUtc),
              _kitchenId,
              ingredientId,
              transition.from.wireCode,
            ],
          );
          if (changed != 1) {
            // The from-status guard lost the race: abort the whole transaction.
            throw const _CompletionAbort(EngineError.seedMissing);
          }
          await txn.insert('stock_event', <String, Object?>{
            'ingredient_id': ingredientId,
            'from_status': transition.from.wireCode,
            'to_status': transition.to.wireCode,
            'reason': transition.reason.wireCode,
            'cooking_session_id': transition.sessionLinked ? id : null,
            'note': transition.sessionLinked ? null : 'review of $id',
            'created_at': isoUtc(nowUtc),
          });
          if (transition.reason == StockReason.restock) {
            restockCorrections += 1;
          }
          eventsWritten += 1;
        }
      }

      // 5. Complete the session with the conditional update.
      final completed = await txn.rawUpdate(
        'UPDATE cooking_sessions SET status = ?, completed_at = ?, '
        '  updated_at = ?, timer_started_at = NULL, '
        '  timer_duration_seconds = NULL '
        'WHERE id = ? AND status = ?',
        <Object?>[
          'completed',
          isoUtc(nowUtc),
          isoUtc(nowUtc),
          id,
          'in_progress',
        ],
      );
      if (completed != 1) {
        // The session moved to a terminal state while we were writing.
        throw const _CompletionAbort(EngineError.sessionNotActive);
      }

      return CompletionResult(
        outcome: CompletionOutcome.completed,
        lines: lines,
        usedItCount: lines
            .where((line) => line.choice == CompletionChoice.usedIt)
            .length,
        usedItUpCount: lines
            .where((line) => line.choice == CompletionChoice.usedItUp)
            .length,
        didntUseCount: lines
            .where((line) => line.choice == CompletionChoice.didntUse)
            .length,
        restockCorrections: restockCorrections,
        eventsWritten: eventsWritten,
      );
    });
  }

  @override
  Future<void> clearSessions() async {
    await _db.delete('cooking_sessions');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<int> _equipmentId(DatabaseExecutor db, String code) async {
    final rows = await db.query(
      'equipment',
      columns: <String>['id'],
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EngineException(
        EngineError.seedMissing,
        'unknown appliance "$code"',
      );
    }
    return rows.single['id']! as int;
  }

  Future<int> _totalSteps(DatabaseExecutor db, int recipeId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM recipe_steps WHERE recipe_id = ?',
      <Object?>[recipeId],
    );
    return rows.single['total']! as int;
  }

  static int _requireId(String sessionId) {
    final id = int.tryParse(sessionId);
    if (id == null) {
      throw const EngineException(EngineError.noActiveSession);
    }
    return id;
  }

  static CompletionResult _rejected(
    List<CompletionLine> lines,
    EngineError error,
  ) {
    return CompletionResult(
      outcome: CompletionOutcome.rejected,
      lines: lines,
      usedItCount: 0,
      usedItUpCount: 0,
      didntUseCount: 0,
      restockCorrections: 0,
      eventsWritten: 0,
      error: error,
    );
  }

  static SessionStatus _statusFromWire(String wire) => switch (wire) {
    'in_progress' => SessionStatus.inProgress,
    'completed' => SessionStatus.completed,
    _ => SessionStatus.abandoned,
  };

  static DateTime? _parseNullable(Object? value) =>
      value is String ? parseUtc(value) : null;
}

/// Thrown inside the completion transaction when a post-write guard fails, so
/// sqflite rolls every write back before the caller sees a rejection.
class _CompletionAbort implements Exception {
  const _CompletionAbort(this.error);

  final EngineError error;
}
