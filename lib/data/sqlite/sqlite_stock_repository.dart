/// Stock repository on SQLite (`docs/08` §4.3, §5.2).
///
/// Every write is one transaction: a conditional status update
/// (`WHERE status = <from>`, `changes == 1`) plus one append-only event. A
/// no-op writes nothing, and a from-status mismatch aborts before any write.
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/models/catalog.dart';
import '../../domain/models/stock.dart';
import '../../domain/rules/stock_rules.dart';
import '../repositories/stock_repository.dart';
import 'app_database.dart';

class SqliteStockRepository implements StockRepository {
  const SqliteStockRepository(
    this._db, {
    this.clock,
    this.ingredientGlosses = const <String, String>{},
  });

  final Database _db;
  final DateTime Function()? clock;

  /// `code -> Filipino gloss` from the fixture catalog; the frozen schema has
  /// no gloss column (see `lib/data/seed/ingredient_gloss_source.dart`).
  final Map<String, String> ingredientGlosses;

  static const int _kitchenId = 1;

  DateTime _now() => (clock ?? () => DateTime.now().toUtc())();

  @override
  Future<List<Ingredient>> listIngredients() async {
    final rows = await _db.rawQuery(
      'SELECT i.id AS id, i.code AS code, i.name AS name, '
      '  i.category AS category, '
      '  (SELECT u.code FROM recipe_ingredients ri '
      '     JOIN units u ON u.id = ri.unit_id '
      '   WHERE ri.ingredient_id = i.id ORDER BY u.id LIMIT 1) AS display_unit '
      'FROM ingredients i ORDER BY i.id',
    );
    return List<Ingredient>.unmodifiable(<Ingredient>[
      for (final row in rows)
        Ingredient(
          code: row['code']! as String,
          name: row['name']! as String,
          filipinoGloss:
              ingredientGlosses[row['code']! as String] ??
              (row['name']! as String),
          category: row['category']! as String,
          displayUnit: (row['display_unit'] as String?) ?? 'g',
          defaultStatus: StockStatus.unknown,
          spriteKey: 'ing_${row['code']! as String}',
        ),
    ]);
  }

  @override
  Future<StockStatus> getStatus(String ingredientCode) async {
    final rows = await _db.rawQuery(
      'SELECT s.status AS status FROM stock_status s '
      'JOIN ingredients i ON i.id = s.ingredient_id '
      'WHERE s.kitchen_id = ? AND i.code = ? LIMIT 1',
      <Object?>[_kitchenId, ingredientCode],
    );
    if (rows.isEmpty) {
      return StockStatus.unknown;
    }
    return StockStatus.fromWire(rows.single['status']! as String);
  }

  @override
  Future<Map<String, StockStatus>> getStatuses(
    Iterable<String> ingredientCodes,
  ) async {
    final codes = ingredientCodes.toList(growable: false);
    final statuses = <String, StockStatus>{
      for (final code in codes) code: StockStatus.unknown,
    };
    if (codes.isEmpty) {
      return statuses;
    }
    final placeholders = List<String>.filled(codes.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT i.code AS code, s.status AS status FROM stock_status s '
      'JOIN ingredients i ON i.id = s.ingredient_id '
      'WHERE s.kitchen_id = ? AND i.code IN ($placeholders)',
      <Object?>[_kitchenId, ...codes],
    );
    for (final row in rows) {
      statuses[row['code']! as String] = StockStatus.fromWire(
        row['status']! as String,
      );
    }
    return statuses;
  }

  @override
  Future<StockEvent?> setStatus({
    required String ingredientCode,
    required StockStatus to,
    required StockReason reason,
    String? cookingSessionId,
    String? note,
  }) async {
    if (reason == StockReason.usedSome || reason == StockReason.usedUp) {
      // Usage events may carry a session link; other reasons may not (DDL CHECK).
    } else if (cookingSessionId != null) {
      throw ArgumentError(
        'cooking_session_id is reserved for used_some/used_up',
      );
    }
    return _db.transaction((txn) async {
      final current = await _currentStatus(txn, ingredientCode);
      if (current == to) {
        return null;
      }
      if (!StockRules.isLegalTransition(
        reason: reason,
        from: current,
        to: to,
      )) {
        throw ArgumentError(
          'illegal stock transition ${current.wireCode} -> ${to.wireCode} '
          'with reason ${reason.wireCode}',
        );
      }
      return _applyTransition(
        txn,
        ingredientCode: ingredientCode,
        from: current,
        to: to,
        reason: reason,
        cookingSessionId: cookingSessionId,
        note: note,
        nowUtc: _now(),
      );
    });
  }

  @override
  Future<StockEvent> recordEvent(StockEventDraft draft) async {
    return _db.transaction((txn) async {
      final current = await _currentStatus(txn, draft.ingredientCode);
      if (current != draft.from) {
        throw StateError(
          'stale stock event for ${draft.ingredientCode}: expected '
          '${current.wireCode}, got ${draft.from.wireCode}',
        );
      }
      if (!StockRules.isLegalTransition(
        reason: draft.reason,
        from: draft.from,
        to: draft.to,
      )) {
        throw ArgumentError(
          'illegal stock transition ${draft.from.wireCode} -> '
          '${draft.to.wireCode} with reason ${draft.reason.wireCode}',
        );
      }
      return _applyTransition(
        txn,
        ingredientCode: draft.ingredientCode,
        from: draft.from,
        to: draft.to,
        reason: draft.reason,
        cookingSessionId: draft.cookingSessionId,
        note: draft.note,
        nowUtc: _now(),
      );
    });
  }

  @override
  Future<List<StockEvent>> listEvents({
    String? ingredientCode,
    String? cookingSessionId,
    int limit = 50,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (ingredientCode != null) {
      where.add('i.code = ?');
      args.add(ingredientCode);
    }
    if (cookingSessionId != null) {
      where.add('e.cooking_session_id = ?');
      args.add(int.tryParse(cookingSessionId));
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await _db.rawQuery(
      'SELECT e.*, i.code AS ingredient_code FROM stock_event e '
      'JOIN ingredients i ON i.id = e.ingredient_id '
      '$clause ORDER BY e.created_at DESC, e.id DESC LIMIT ? OFFSET ?',
      <Object?>[...args, limit, offset],
    );
    return List<StockEvent>.unmodifiable(<StockEvent>[
      for (final row in rows) _eventFromRow(row),
    ]);
  }

  Future<StockStatus> _currentStatus(
    DatabaseExecutor db,
    String ingredientCode,
  ) async {
    final rows = await db.rawQuery(
      'SELECT s.status AS status FROM stock_status s '
      'JOIN ingredients i ON i.id = s.ingredient_id '
      'WHERE s.kitchen_id = ? AND i.code = ? LIMIT 1',
      <Object?>[_kitchenId, ingredientCode],
    );
    if (rows.isEmpty) {
      throw StateError('seed missing: no stock_status row for $ingredientCode');
    }
    return StockStatus.fromWire(rows.single['status']! as String);
  }

  Future<StockEvent> _applyTransition(
    DatabaseExecutor txn, {
    required String ingredientCode,
    required StockStatus from,
    required StockStatus to,
    required StockReason reason,
    required String? cookingSessionId,
    required String? note,
    required DateTime nowUtc,
  }) async {
    // The from-status guard: the update only lands while the row still has the
    // status the event claims (`changes == 1` required).
    final changed = await txn.rawUpdate(
      'UPDATE stock_status SET status = ?, updated_at = ? '
      'WHERE kitchen_id = ? AND status = ? AND ingredient_id = '
      '  (SELECT id FROM ingredients WHERE code = ?)',
      <Object?>[
        to.wireCode,
        isoUtc(nowUtc),
        _kitchenId,
        from.wireCode,
        ingredientCode,
      ],
    );
    if (changed != 1) {
      throw StateError(
        'stale stock status for $ingredientCode: guarded update matched '
        '$changed rows',
      );
    }
    final sessionId = cookingSessionId == null
        ? null
        : int.tryParse(cookingSessionId);
    final id = await txn.rawInsert(
      'INSERT INTO stock_event (ingredient_id, from_status, to_status, reason, '
      '  cooking_session_id, note, created_at) '
      'VALUES ((SELECT id FROM ingredients WHERE code = ?), ?, ?, ?, ?, ?, ?)',
      <Object?>[
        ingredientCode,
        from.wireCode,
        to.wireCode,
        reason.wireCode,
        sessionId,
        note,
        isoUtc(nowUtc),
      ],
    );
    return StockEvent(
      id: '$id',
      ingredientCode: ingredientCode,
      from: from,
      to: to,
      reason: reason,
      cookingSessionId: cookingSessionId,
      note: note,
      createdAt: nowUtc,
    );
  }

  StockEvent _eventFromRow(Map<String, Object?> row) {
    return StockEvent(
      id: '${row['id']}',
      ingredientCode: row['ingredient_code']! as String,
      from: StockStatus.fromWire(row['from_status']! as String),
      to: StockStatus.fromWire(row['to_status']! as String),
      reason:
          StockReason.fromWire(row['reason']! as String) ??
          StockReason.correction,
      cookingSessionId: row['cooking_session_id']?.toString(),
      note: row['note'] as String?,
      createdAt: parseUtc(row['created_at']! as String),
    );
  }
}
