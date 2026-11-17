/// Mutable in-memory state shared by the Phase A fixture repositories.
///
/// One object per app run: it starts from the parsed [FixtureBundle] and is
/// reset by "Reset demo data". Nothing is persisted; relaunching reloads the
/// JSON (documented Phase A behaviour, `docs/08` §6.1).
library;

import '../../../domain/models/kitchen.dart';
import '../../../domain/models/stock.dart';
import 'fixture_bundle.dart';

typedef Clock = DateTime Function();

class FixtureData {
  FixtureData({required this.bundle, Clock? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc()),
      statuses = Map<String, StockStatus>.of(bundle.statuses),
      ownedEquipmentCodes = Set<String>.of(bundle.ownedEquipmentCodes),
      kitchen = bundle.kitchen;

  final FixtureBundle bundle;
  final Clock _clock;

  /// Current tri-state per ingredient code.
  final Map<String, StockStatus> statuses;

  /// Appliances the kitchen owns.
  final Set<String> ownedEquipmentCodes;

  /// The one kitchen profile.
  Kitchen kitchen;

  /// Append-only in-memory event log.
  final List<StockEvent> events = <StockEvent>[];

  int _eventSeq = 0;

  void reset() {
    statuses
      ..clear()
      ..addAll(bundle.statuses);
    ownedEquipmentCodes
      ..clear()
      ..addAll(bundle.ownedEquipmentCodes);
    kitchen = bundle.kitchen;
    events.clear();
    _eventSeq = 0;
  }

  /// Whether any event exists for [ingredientCode]; the first recorded status
  /// of an ingredient uses the `initial` reason (`docs/06` §3.3).
  bool hasEventsFor(String ingredientCode) =>
      events.any((event) => event.ingredientCode == ingredientCode);

  /// Appends one event and applies its target status. Callers validate
  /// legality; this is the shared write primitive.
  StockEvent append({
    required String ingredientCode,
    required StockStatus from,
    required StockStatus to,
    required StockReason reason,
    String? cookingSessionId,
    String? note,
  }) {
    _eventSeq += 1;
    final event = StockEvent(
      id: 'evt_$_eventSeq',
      ingredientCode: ingredientCode,
      from: from,
      to: to,
      reason: reason,
      cookingSessionId: cookingSessionId,
      note: note,
      createdAt: _clock(),
    );
    statuses[ingredientCode] = to;
    events.add(event);
    return event;
  }
}
