/// History (`docs/07` §7 screen 9): completed and abandoned cooks with the
/// stock events they wrote, expandable in place — no extra route.
library;

import 'package:flutter/foundation.dart';

import '../../data/repositories/stock_repository.dart';
import '../../domain/guide/guide_models.dart';
import '../../domain/models/stock.dart';

class HistorySession {
  const HistorySession({required this.session, required this.events});

  final GuidedSession session;
  final List<StockEvent> events;
}

class HistoryController extends ChangeNotifier {
  HistoryController({required this.sessions, required this.stockRepository});

  final Future<List<GuidedSession>> Function() sessions;
  final StockRepository stockRepository;

  bool _loading = true;
  List<HistorySession> _entries = const <HistorySession>[];
  List<StockEvent> _events = const <StockEvent>[];
  final Set<String> _expanded = <String>{};

  bool get isLoading => _loading;
  List<HistorySession> get entries => _entries;

  /// Every stock event, including the review restock rows that carry no
  /// `cooking_session_id` (`docs/07` screen 9's Stock events segment).
  List<StockEvent> get events => _events;

  bool isExpanded(String sessionId) => _expanded.contains(sessionId);

  /// Loads every terminal session and its linked events.
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final allSessions = await sessions();
    final entries = <HistorySession>[];
    for (final session in allSessions) {
      if (session.isActive) {
        continue;
      }
      final events = await stockRepository.listEvents(
        cookingSessionId: session.id,
        limit: 100,
      );
      entries.add(HistorySession(session: session, events: events));
    }
    _entries = List<HistorySession>.unmodifiable(entries);
    _events = List<StockEvent>.unmodifiable(
      await stockRepository.listEvents(limit: 200),
    );
    _loading = false;
    notifyListeners();
  }

  void toggle(String sessionId) {
    if (!_expanded.remove(sessionId)) {
      _expanded.add(sessionId);
    }
    notifyListeners();
  }

  /// `Have → Low` and similar, with the reason code.
  static String eventLine(StockEvent event) =>
      '${event.from.label} → ${event.to.label} · '
      '${_reasonLabel(event.reason)}';

  /// Ingredient code as a readable row label.
  static String ingredientLabel(StockEvent event) =>
      event.ingredientCode.replaceAll('_', ' ');

  /// Whether the event belongs to a cook or is a review-time correction.
  static String linkLabel(StockEvent event) => event.cookingSessionId != null
      ? 'linked to a cook'
      : 'review note (no cook link)';

  static String _reasonLabel(StockReason reason) => switch (reason) {
    StockReason.initial => 'first record',
    StockReason.restock => 'restocked',
    StockReason.usedSome => 'used some',
    StockReason.usedUp => 'used up',
    StockReason.waste => 'wasted',
    StockReason.correction => 'corrected',
  };

  static String statusLabel(SessionStatus status) => switch (status) {
    SessionStatus.completed => 'Completed',
    SessionStatus.abandoned => 'Abandoned',
    SessionStatus.inProgress => 'In progress',
  };
}
