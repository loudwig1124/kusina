/// Phase A stock repository: in-memory tri-state plus an append-only event list.
///
/// The write rules mirror the SQLite implementation that replaces it in
/// Phase B: one legal transition per call, no-op writes nothing, and the
/// `from` status must equal the current one.
library;

import '../../../domain/models/catalog.dart';
import '../../../domain/models/stock.dart';
import '../../../domain/rules/stock_rules.dart';
import '../stock_repository.dart';
import 'fixture_data.dart';

class FixtureStockRepository implements StockRepository {
  const FixtureStockRepository(this._data);

  final FixtureData _data;

  @override
  Future<List<Ingredient>> listIngredients() async => _data.bundle.ingredients;

  @override
  Future<StockStatus> getStatus(String ingredientCode) async =>
      _data.statuses[ingredientCode] ?? StockStatus.unknown;

  @override
  Future<Map<String, StockStatus>> getStatuses(
    Iterable<String> ingredientCodes,
  ) async => {
    for (final code in ingredientCodes)
      code: _data.statuses[code] ?? StockStatus.unknown,
  };

  @override
  Future<StockEvent?> setStatus({
    required String ingredientCode,
    required StockStatus to,
    required StockReason reason,
    String? cookingSessionId,
    String? note,
  }) async {
    final from = await getStatus(ingredientCode);
    if (from == to) {
      return null;
    }
    if (!StockRules.isLegalTransition(reason: reason, from: from, to: to)) {
      throw ArgumentError(
        'illegal stock transition ${from.wireCode} -> ${to.wireCode} '
        'with reason ${reason.wireCode}',
      );
    }
    return _data.append(
      ingredientCode: ingredientCode,
      from: from,
      to: to,
      reason: reason,
      cookingSessionId: cookingSessionId,
      note: note,
    );
  }

  @override
  Future<StockEvent> recordEvent(StockEventDraft draft) async {
    final current = await getStatus(draft.ingredientCode);
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
    return _data.append(
      ingredientCode: draft.ingredientCode,
      from: draft.from,
      to: draft.to,
      reason: draft.reason,
      cookingSessionId: draft.cookingSessionId,
      note: draft.note,
    );
  }

  @override
  Future<List<StockEvent>> listEvents({
    String? ingredientCode,
    String? cookingSessionId,
    int limit = 50,
    int offset = 0,
  }) async {
    final filtered =
        _data.events
            .where(
              (event) =>
                  (ingredientCode == null ||
                      event.ingredientCode == ingredientCode) &&
                  (cookingSessionId == null ||
                      event.cookingSessionId == cookingSessionId),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (offset >= filtered.length) {
      return const <StockEvent>[];
    }
    return filtered.skip(offset).take(limit).toList(growable: false);
  }
}
