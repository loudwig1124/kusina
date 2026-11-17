/// Tri-state stock presence for one ingredient.
///
/// Contract: `docs/06` §3.3 (A3) and `docs/07` §5.1. There are exactly four
/// stored values, no quantities and no units: `unknown` is a stored "I don't
/// know" and never blocks, `out` is missing and blocks, `have`/`low` are
/// available while `low` warns.
enum StockStatus {
  unknown('unknown', 'Probably have'),
  have('have', 'Have'),
  low('low', 'Low'),
  out('out', 'Out');

  const StockStatus(this.wireCode, this.label);

  /// Stable storage code (`stock_status.status`); never localised.
  final String wireCode;

  /// Locked user-facing label (`docs/06` §3.4). Title case, verbatim.
  final String label;

  /// Available for cooking: `have` and `low` (a `low` line also warns).
  bool get isAvailable => this == StockStatus.have || this == StockStatus.low;

  /// A required ingredient in this state blocks the recipe.
  bool get isMissing => this == StockStatus.out;

  /// A required ingredient in this state is flagged "probably have — confirm".
  bool get needsConfirmation => this == StockStatus.unknown;

  /// Parses a wire code; unknown values fall back to [StockStatus.unknown]
  /// because "no row" and "I don't know" are the same presence state.
  static StockStatus fromWire(String? value) {
    for (final status in StockStatus.values) {
      if (status.wireCode == value) {
        return status;
      }
    }
    return StockStatus.unknown;
  }
}

/// Why a stock event was written (`docs/06` §3.3). The reason decides which
/// transitions are legal; a no-op transition is never legal.
enum StockReason {
  initial('initial'),
  restock('restock'),
  usedSome('used_some'),
  usedUp('used_up'),
  waste('waste'),
  correction('correction');

  const StockReason(this.wireCode);

  /// Stable storage code (`stock_event.reason`).
  final String wireCode;

  static StockReason? fromWire(String? value) {
    for (final reason in StockReason.values) {
      if (reason.wireCode == value) {
        return reason;
      }
    }
    return null;
  }
}

/// One append-only stock transition (`docs/06` §3.3 A3).
class StockEvent {
  const StockEvent({
    required this.id,
    required this.ingredientCode,
    required this.from,
    required this.to,
    required this.reason,
    this.cookingSessionId,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String ingredientCode;
  final StockStatus from;
  final StockStatus to;
  final StockReason reason;
  final String? cookingSessionId;
  final String? note;
  final DateTime createdAt;

  StockEvent copyWith({String? id}) => StockEvent(
    id: id ?? this.id,
    ingredientCode: ingredientCode,
    from: from,
    to: to,
    reason: reason,
    cookingSessionId: cookingSessionId,
    note: note,
    createdAt: createdAt,
  );

  @override
  String toString() =>
      'StockEvent($id, $ingredientCode: ${from.wireCode}->${to.wireCode}, '
      '${reason.wireCode})';
}

/// The same transition before persistence assigns an id/timestamp.
class StockEventDraft {
  const StockEventDraft({
    required this.ingredientCode,
    required this.from,
    required this.to,
    required this.reason,
    this.cookingSessionId,
    this.note,
  });

  final String ingredientCode;
  final StockStatus from;
  final StockStatus to;
  final StockReason reason;
  final String? cookingSessionId;
  final String? note;
}
