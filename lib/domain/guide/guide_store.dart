/// The guide store seam (`docs/09` §11.4) and the Phase A in-memory adapter.
///
/// Pure Dart. The store is the only thing that touches persistence, and it does
/// so through small injected readers/writers typed with domain models — so this
/// file imports no Flutter, no sqflite and no repository contract. Phase B
/// implements the same seam over SQLite and swaps it in `lib/app/di.dart`.
library;

import '../models/recipe.dart';
import '../models/stock.dart';
import 'guide_models.dart';
import 'guide_rules.dart';

typedef RecipeReader = Future<RecipeDetail?> Function(String slug);
typedef StatusReader = Future<Map<String, StockStatus>> Function(
  List<String> ingredientCodes,
);
typedef StatusWriter = Future<void> Function(
  String ingredientCode,
  StockStatus to,
  StockReason reason, {
  String? cookingSessionId,
  String? note,
});
typedef OwnedEquipmentReader = Future<Set<String>> Function();

/// Everything the engine persists (`docs/09` §11.4).
abstract interface class GuideStore {
  /// The recipe content for a slug, or null when it is not seeded.
  Future<RecipeDetail?> loadRecipe(String slug);

  Future<GuidedSession?> loadActiveSession();

  Future<GuidedSession?> loadSession(String sessionId);

  /// Stores [session] and returns it with its assigned id.
  Future<GuidedSession> insertSession(GuidedSession session);

  Future<void> updateStepNumber(
    String sessionId,
    int stepNumber,
    DateTime nowUtc,
  );

  Future<void> writeTimer(
    String sessionId,
    DateTime? startedAtUtc,
    int? durationSeconds,
  );

  Future<void> writeLastSeen(String sessionId, DateTime atUtc);

  Future<GuidedSession> abandonSession(String sessionId, DateTime nowUtc);

  /// The only completion write path (`docs/09` §8.5): re-reads the statuses,
  /// validates every line, applies the transitions and completes the session.
  /// Returns `alreadyCompleted` with zero writes for a terminal session.
  Future<CompletionResult> completeAtomically({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  });

  Future<Map<String, StockStatus>> statusesOf(List<String> ingredientCodes);

  Future<Set<String>> ownedEquipmentCodes();

  /// All sessions, newest first (history and tests).
  Future<List<GuidedSession>> sessions();

  /// Drops every session (demo reset / test isolation).
  Future<void> clearSessions();
}

/// Phase A store: sessions and their pinned paths in memory, stock writes
/// delegated to the injected writer (the fixture stock repository).
class InMemoryGuideStore implements GuideStore {
  InMemoryGuideStore({
    required this.recipeReader,
    required this.statusReader,
    required this.statusWriter,
    required this.ownedEquipmentReader,
    this.kitchenId = 'demo-kitchen',
  });

  final RecipeReader recipeReader;
  final StatusReader statusReader;
  final StatusWriter statusWriter;
  final OwnedEquipmentReader ownedEquipmentReader;
  final String kitchenId;

  final Map<String, GuidedSession> _sessions = <String, GuidedSession>{};
  int _sequence = 0;

  @override
  Future<RecipeDetail?> loadRecipe(String slug) => recipeReader(slug);

  @override
  Future<GuidedSession?> loadActiveSession() async {
    for (final session in _sessions.values) {
      if (session.isActive) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<GuidedSession?> loadSession(String sessionId) async =>
      _sessions[sessionId];

  /// Hydrates a session exactly as persisted. Phase B's SQLite store reads its
  /// rows through the same contract; Phase A uses this to model a cold start.
  Future<void> restoreSession(GuidedSession session) async {
    _sessions[session.id] = session;
  }

  @override
  Future<GuidedSession> insertSession(GuidedSession session) async {
    final active = await loadActiveSession();
    if (active != null) {
      throw const EngineException(
        EngineError.activeSessionExists,
        'one in-progress session per kitchen',
      );
    }
    _sequence += 1;
    final stored = GuidedSession(
      id: session.id.isEmpty ? 's$_sequence' : session.id,
      kitchenId: session.kitchenId.isEmpty ? kitchenId : session.kitchenId,
      recipeSlug: session.recipeSlug,
      recipeName: session.recipeName,
      status: SessionStatus.inProgress,
      currentStepNumber: 1,
      totalSteps: session.totalSteps,
      startedAtUtc: session.startedAtUtc,
      lastSeenAtUtc: session.lastSeenAtUtc,
      timerStartedAtUtc: null,
      timerDurationSeconds: null,
      startedWithoutAvailability: session.startedWithoutAvailability,
      missingCodes: session.missingCodes,
      path: session.path,
    );
    _sessions[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateStepNumber(
    String sessionId,
    int stepNumber,
    DateTime nowUtc,
  ) async {
    final session = _requireSession(sessionId);
    _sessions[sessionId] = session.copyWith(
      currentStepNumber: stepNumber,
      lastSeenAtUtc: nowUtc,
      clearTimer: true,
    );
  }

  @override
  Future<void> writeTimer(
    String sessionId,
    DateTime? startedAtUtc,
    int? durationSeconds,
  ) async {
    final session = _requireSession(sessionId);
    _sessions[sessionId] = startedAtUtc == null
        ? session.copyWith(clearTimer: true)
        : session.copyWith(
            timerStartedAtUtc: startedAtUtc,
            timerDurationSeconds: durationSeconds,
          );
  }

  @override
  Future<void> writeLastSeen(String sessionId, DateTime atUtc) async {
    final session = _requireSession(sessionId);
    _sessions[sessionId] = session.copyWith(lastSeenAtUtc: atUtc);
  }

  @override
  Future<GuidedSession> abandonSession(
    String sessionId,
    DateTime nowUtc,
  ) async {
    final session = _requireSession(sessionId);
    final abandoned = session.copyWith(
      status: SessionStatus.abandoned,
      lastSeenAtUtc: nowUtc,
      clearTimer: true,
    );
    _sessions[sessionId] = abandoned;
    return abandoned;
  }

  @override
  Future<Map<String, StockStatus>> statusesOf(List<String> ingredientCodes) =>
      statusReader(ingredientCodes);

  @override
  Future<Set<String>> ownedEquipmentCodes() => ownedEquipmentReader();

  @override
  Future<List<GuidedSession>> sessions() async {
    final all = _sessions.values.toList()
      ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
    return List<GuidedSession>.unmodifiable(all);
  }

  @override
  Future<void> clearSessions() async {
    _sessions.clear();
    _sequence = 0;
  }

  @override
  Future<CompletionResult> completeAtomically({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return CompletionResult(
        outcome: CompletionOutcome.rejected,
        lines: lines,
        usedItCount: 0,
        usedItUpCount: 0,
        didntUseCount: 0,
        restockCorrections: 0,
        eventsWritten: 0,
        error: EngineError.seedMissing,
      );
    }
    if (session.status == SessionStatus.completed) {
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
    if (session.status != SessionStatus.inProgress) {
      return CompletionResult(
        outcome: CompletionOutcome.rejected,
        lines: lines,
        usedItCount: 0,
        usedItUpCount: 0,
        didntUseCount: 0,
        restockCorrections: 0,
        eventsWritten: 0,
        error: EngineError.sessionNotActive,
      );
    }
    if (!session.isReview) {
      return CompletionResult(
        outcome: CompletionOutcome.rejected,
        lines: lines,
        usedItCount: 0,
        usedItUpCount: 0,
        didntUseCount: 0,
        restockCorrections: 0,
        eventsWritten: 0,
        error: EngineError.completionIncomplete,
      );
    }

    // Re-read the live statuses; the review snapshot is never trusted.
    final current = await statusesOf(<String>[
      for (final line in lines) line.ingredientCode,
    ]);

    // Validate everything before the first write so a bad line writes nothing.
    final planned = <StockTransition>[];
    for (final line in lines) {
      final liveStatus = current[line.ingredientCode];
      if (liveStatus == null) {
        return CompletionResult(
          outcome: CompletionOutcome.rejected,
          lines: lines,
          usedItCount: 0,
          usedItUpCount: 0,
          didntUseCount: 0,
          restockCorrections: 0,
          eventsWritten: 0,
          error: EngineError.seedMissing,
        );
      }
      final effectiveStatus =
          line.restockToHave && liveStatus != StockStatus.have
          ? StockStatus.have
          : liveStatus;
      if (!isChoiceAllowed(effectiveStatus, line.choice)) {
        return CompletionResult(
          outcome: CompletionOutcome.rejected,
          lines: lines,
          usedItCount: 0,
          usedItUpCount: 0,
          didntUseCount: 0,
          restockCorrections: 0,
          eventsWritten: 0,
          error: EngineError.invalidCompletionLine,
        );
      }
      planned.addAll(
        completionTransitionsFor(
          ingredientCode: line.ingredientCode,
          current: liveStatus,
          choice: line.choice,
          restockToHave: line.restockToHave,
        ),
      );
    }

    var restockCorrections = 0;
    var eventsWritten = 0;
    for (final transition in planned) {
      if (transition.reason == StockReason.restock) {
        restockCorrections += 1;
      }
      await statusWriter(
        transition.ingredientCode,
        transition.to,
        transition.reason,
        cookingSessionId: transition.sessionLinked ? sessionId : null,
        note: transition.sessionLinked ? null : 'review of $sessionId',
      );
      eventsWritten += 1;
    }

    _sessions[sessionId] = session.copyWith(
      status: SessionStatus.completed,
      completedAtUtc: nowUtc,
      lastSeenAtUtc: nowUtc,
      clearTimer: true,
    );

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
  }

  GuidedSession _requireSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const EngineException(EngineError.noActiveSession);
    }
    return session;
  }
}
