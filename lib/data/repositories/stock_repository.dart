/// Stock contract (`docs/08` §5.2). Presencia only: no quantities, no units.
///
/// Pure Dart; the fixture implementation keeps state in memory for Phase A and
/// the SQLite implementation swaps in behind the same port for Phase B.
library;

import '../../domain/models/catalog.dart';
import '../../domain/models/stock.dart';

abstract interface class StockRepository {
  Future<List<Ingredient>> listIngredients();

  Future<StockStatus> getStatus(String ingredientCode);

  Future<Map<String, StockStatus>> getStatuses(
    Iterable<String> ingredientCodes,
  );

  /// Applies one manual status change and appends the matching event
  /// atomically. Returns null when [to] equals the current status (a no-op
  /// writes nothing). Rejects a reason/transition mismatch.
  Future<StockEvent?> setStatus({
    required String ingredientCode,
    required StockStatus to,
    required StockReason reason,
    String? cookingSessionId,
    String? note,
  });

  /// Append-only primitive; the caller must pass the current status as `from`.
  Future<StockEvent> recordEvent(StockEventDraft draft);

  Future<List<StockEvent>> listEvents({
    String? ingredientCode,
    String? cookingSessionId,
    int limit = 50,
    int offset = 0,
  });
}
