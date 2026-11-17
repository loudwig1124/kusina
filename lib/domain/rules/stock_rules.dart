/// Legal stock transitions and the manual-edit reason mapping
/// (`docs/06` §3.3 A3 / `docs/08` §3.1).
///
/// Pure Dart: one tap in Inventory becomes one event with one legal reason, and
/// a no-op never writes anything.
library;

import '../models/stock.dart';

class StockRules {
  const StockRules._();

  /// `initial | restock | used_some | used_up | waste | correction` rules from
  /// `docs/06` §3.3. A reason outside its row is rejected; a no-op is illegal.
  static bool isLegalTransition({
    required StockReason reason,
    required StockStatus from,
    required StockStatus to,
  }) {
    if (from == to) {
      return false;
    }
    return switch (reason) {
      StockReason.initial => from == StockStatus.unknown,
      StockReason.restock =>
        to == StockStatus.have &&
            (from == StockStatus.unknown ||
                from == StockStatus.out ||
                from == StockStatus.low),
      StockReason.usedSome =>
        to == StockStatus.low &&
            (from == StockStatus.have || from == StockStatus.unknown),
      StockReason.usedUp =>
        to == StockStatus.out &&
            (from == StockStatus.have ||
                from == StockStatus.low ||
                from == StockStatus.unknown),
      StockReason.waste =>
        to == StockStatus.out &&
            (from == StockStatus.have || from == StockStatus.low),
      StockReason.correction => true,
    };
  }

  /// The reason a manual Inventory/Ingredient-detail tap writes.
  ///
  /// Returns null for a no-op (the caller must not write an event). The
  /// first recorded status for an ingredient is `initial`; later taps use the
  /// domain reason that describes the change (`restock`, `used_some`,
  /// `used_up`) and fall back to `correction` when no domain reason fits.
  static StockReason? reasonForManualEdit({
    required StockStatus from,
    required StockStatus to,
    bool isFirstRecord = false,
  }) {
    if (from == to) {
      return null;
    }
    if (isFirstRecord && from == StockStatus.unknown) {
      return StockReason.initial;
    }
    return switch (to) {
      StockStatus.have => StockReason.restock,
      StockStatus.low =>
        from == StockStatus.have || from == StockStatus.unknown
            ? StockReason.usedSome
            : StockReason.correction,
      StockStatus.out =>
        from == StockStatus.have ||
                from == StockStatus.low ||
                from == StockStatus.unknown
            ? StockReason.usedUp
            : StockReason.correction,
      StockStatus.unknown => StockReason.correction,
    };
  }
}
