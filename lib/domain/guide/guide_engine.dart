/// The guided-cooking engine (`docs/09` §11.3): pure Dart, no Flutter, no clock
/// reads, no SQL.
///
/// Every call takes an injected `nowUtc`; the only persistence is the
/// [GuideStore] seam. The engine never auto-advances, never completes on a timer
/// and never rewrites `timer_started_at`.
library;

import '../models/recipe.dart';
import '../rules/availability_service.dart';
import 'guide_models.dart';
import 'guide_rules.dart';
import 'guide_store.dart';

abstract interface class GuidedCookingEngine {
  /// Starts a cook for the cook's explicit method pick (`docs/09` §5.3).
  ///
  /// Returns the existing active session instead of writing a second one, the
  /// availability result when a blocked dish was not explicitly overridden, and
  /// `methodChoiceRequired` when a method dish is asked for with no pick.
  Future<StartResult> start({
    required String recipeSlug,
    required String? methodKey,
    required bool guideAnyway,
    required DateTime nowUtc,
  });

  Future<StepView> advance({
    required String sessionId,
    required DateTime nowUtc,
  });

  Future<StepView> currentStep({
    required String sessionId,
    required DateTime nowUtc,
  });

  Future<TimerState> timerState({
    required String sessionId,
    required DateTime nowUtc,
  });

  /// Read-only resume read (`docs/09` §5.4); the UI then calls [markSeen].
  Future<ResumeInfo> onResume({
    required String sessionId,
    required DateTime nowUtc,
  });

  Future<List<CompletionLine>> review({required String sessionId});

  Future<CompletionResult> complete({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  });

  Future<GuidedSession> abandon({
    required String sessionId,
    required bool confirmed,
    required DateTime nowUtc,
  });

  Future<AvailabilityResult> checkAvailability({
    required String recipeSlug,
    required String? methodKey,
  });

  Future<GuidedSession?> activeSession();

  Future<GuidedSession?> session(String sessionId);

  /// The recipe content for a slug (label lookups on the guide header).
  Future<RecipeDetail?> recipe(String slug);

  Future<TimerState> startTimer({
    required String sessionId,
    required DateTime nowUtc,
  });

  Future<void> clearTimer({required String sessionId});

  Future<void> markSeen({required String sessionId, required DateTime nowUtc});

  Future<void> onPause({required String sessionId, required DateTime nowUtc});
}

/// The Phase A engine over a [GuideStore] and the presence rule.
class LocalGuidedCookingEngine implements GuidedCookingEngine {
  LocalGuidedCookingEngine({
    required this.store,
    this.availabilityService = const PresenceAvailabilityService(),
    String Function()? newSessionId,
    this.kitchenId = 'demo-kitchen',
  }) : _newSessionId = newSessionId ?? _defaultSessionId;

  final GuideStore store;
  final AvailabilityService availabilityService;
  final String kitchenId;
  final String Function() _newSessionId;

  /// Newest instant this engine observed per session. It is what separates
  /// `done` (deadline crossed on screen) from `overrun` (crossed while away).
  final Map<String, DateTime> _lastObserved = <String, DateTime>{};

  static int _sessionCounter = 0;
  static String _defaultSessionId() {
    _sessionCounter += 1;
    return 'guide-$_sessionCounter';
  }

  @override
  Future<GuidedSession?> activeSession() => store.loadActiveSession();

  @override
  Future<GuidedSession?> session(String sessionId) =>
      store.loadSession(sessionId);

  @override
  Future<RecipeDetail?> recipe(String slug) => store.loadRecipe(slug);

  @override
  Future<AvailabilityResult> checkAvailability({
    required String recipeSlug,
    required String? methodKey,
  }) async {
    final recipe = await _requireRecipe(recipeSlug);
    return _evaluate(recipe, methodKey);
  }

  @override
  Future<StartResult> start({
    required String recipeSlug,
    required String? methodKey,
    required bool guideAnyway,
    required DateTime nowUtc,
  }) async {
    final active = await store.loadActiveSession();
    if (active != null) {
      return StartResult(activeSession: active);
    }
    final recipe = await store.loadRecipe(recipeSlug);
    if (recipe == null) {
      return const StartResult(error: EngineError.recipeNotFound);
    }
    if (lintRecipe(recipe).isNotEmpty) {
      return const StartResult(error: EngineError.seedInvalid);
    }
    final EquipmentPath path;
    final AvailabilityResult availability;
    try {
      path = planPath(recipe, methodKey);
      availability = await _evaluate(recipe, methodKey);
    } on EngineException catch (error) {
      return StartResult(error: error.code);
    }

    if (availability.state == AvailabilityState.blocked && !guideAnyway) {
      return StartResult(blockedBy: availability);
    }
    final session = await store.insertSession(
      GuidedSession(
        id: _newSessionId(),
        kitchenId: kitchenId,
        recipeSlug: recipe.slug,
        recipeName: recipe.name,
        status: SessionStatus.inProgress,
        currentStepNumber: 1,
        totalSteps: recipe.steps.length,
        startedAtUtc: nowUtc,
        lastSeenAtUtc: nowUtc,
        startedWithoutAvailability:
            availability.state == AvailabilityState.blocked,
        missingCodes: availability.state == AvailabilityState.blocked
            ? availability.missingCodes
            : const <String>[],
        path: path,
      ),
    );
    _observe(session.id, nowUtc);
    return StartResult(session: session);
  }

  @override
  Future<StepView> currentStep({
    required String sessionId,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
    _requireActive(session);
    if (session.isReview) {
      throw const EngineException(
        EngineError.alreadyAtReview,
        'open the usage review instead',
      );
    }
    _observe(sessionId, nowUtc);
    return stepViewFor(
      session,
      nowUtc: nowUtc,
      inMemoryLastSeenUtc: _lastObserved[sessionId],
    );
  }

  @override
  Future<StepView> advance({
    required String sessionId,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
    _requireActive(session);
    if (session.isReview) {
      throw const EngineException(EngineError.alreadyAtReview);
    }
    if (session.currentStepNumber < 1 ||
        session.currentStepNumber > session.totalSteps) {
      throw EngineException(
        EngineError.stepOutOfRange,
        'step ${session.currentStepNumber} of ${session.totalSteps}',
      );
    }
    final nextStep = session.currentStepNumber + 1;
    await store.updateStepNumber(sessionId, nextStep, nowUtc);
    _lastObserved.remove(sessionId);
    _observe(sessionId, nowUtc);
    final updated = await _requireSession(sessionId);
    return stepViewFor(
      updated,
      nowUtc: nowUtc,
      inMemoryLastSeenUtc: _lastObserved[sessionId],
    );
  }

  @override
  Future<TimerState> timerState({
    required String sessionId,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
    _observe(sessionId, nowUtc);
    return _timerFor(session, nowUtc);
  }

  @override
  Future<TimerState> startTimer({
    required String sessionId,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
    _requireActive(session);
    if (session.isReview) {
      throw const EngineException(EngineError.timerNotAvailable);
    }
    if (session.timerStartedAtUtc != null) {
      throw const EngineException(EngineError.timerAlreadyRunning);
    }
    final pinned = session.path.step(session.currentStepNumber);
    final duration = pinned?.snapshot.durationSeconds;
    if (duration == null || duration <= 0) {
      throw const EngineException(EngineError.timerNotAvailable);
    }
    await store.writeTimer(sessionId, nowUtc, duration);
    await store.writeLastSeen(sessionId, nowUtc);
    _observe(sessionId, nowUtc);
    final updated = await _requireSession(sessionId);
    return _timerFor(updated, nowUtc);
  }

  @override
  Future<void> clearTimer({required String sessionId}) async {
    final session = await _requireSession(sessionId);
    if (session.timerStartedAtUtc == null) {
      return;
    }
    await store.writeTimer(sessionId, null, null);
  }

  @override
  Future<ResumeInfo> onResume({
    required String sessionId,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
    final timer = _timerFor(session, nowUtc);
    final lastSeen = _newest(<DateTime?>[
      session.lastSeenAtUtc,
      _lastObserved[sessionId],
      session.startedAtUtc,
    ]);
    final awaySince = nowUtc.difference(lastSeen);
    final finishedAgo = timer.overdue;
    final stale =
        nowUtc.difference(session.startedAtUtc) > const Duration(hours: 24);
    return ResumeInfo(
      session: session,
      step: session.isReview
          ? null
          : stepViewFor(
              session,
              nowUtc: nowUtc,
              inMemoryLastSeenUtc: _lastObserved[sessionId],
            ),
      isReview: session.isReview,
      timer: timer,
      awaySince: awaySince.isNegative ? Duration.zero : awaySince,
      timerFinishedAgo: finishedAgo,
      stale: stale,
      resumeCopy: resumeCopy(
        session: session,
        timer: timer,
        awaySince: awaySince.isNegative ? Duration.zero : awaySince,
      ),
    );
  }

  @override
  Future<void> markSeen({
    required String sessionId,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
    if (session.status.isTerminal) {
      return;
    }
    await store.writeLastSeen(sessionId, nowUtc);
    _observe(sessionId, nowUtc);
  }

  @override
  Future<void> onPause({required String sessionId, required DateTime nowUtc}) =>
      markSeen(sessionId: sessionId, nowUtc: nowUtc);

  @override
  Future<List<CompletionLine>> review({required String sessionId}) async {
    final session = await _requireSession(sessionId);
    if (!session.isReview) {
      throw const EngineException(
        EngineError.completionIncomplete,
        'advance to the review first',
      );
    }
    final recipe = await _requireRecipe(session.recipeSlug);
    final statuses = await store.statusesOf(<String>[
      for (final line in recipe.lines) line.ingredientCode,
    ]);
    return defaultCompletionLines(recipe, statuses);
  }

  @override
  Future<CompletionResult> complete({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  }) async {
    final session = await _requireSession(sessionId);
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
    _requireActive(session);
    if (!session.isReview) {
      throw const EngineException(EngineError.completionIncomplete);
    }
    final recipe = await _requireRecipe(session.recipeSlug);
    final ingredientCodes = <String>{
      for (final line in recipe.lines) line.ingredientCode,
    };
    for (final line in lines) {
      if (!ingredientCodes.contains(line.ingredientCode)) {
        throw EngineException(
          EngineError.invalidCompletionLine,
          '${line.ingredientCode} is not part of ${recipe.slug}',
        );
      }
    }
    return store.completeAtomically(
      sessionId: sessionId,
      lines: lines,
      nowUtc: nowUtc,
    );
  }

  @override
  Future<GuidedSession> abandon({
    required String sessionId,
    required bool confirmed,
    required DateTime nowUtc,
  }) async {
    if (!confirmed) {
      throw const EngineException(EngineError.abandonNotConfirmed);
    }
    final session = await _requireSession(sessionId);
    _requireActive(session);
    final abandoned = await store.abandonSession(sessionId, nowUtc);
    _lastObserved.remove(sessionId);
    return abandoned;
  }

  /// Availability for the cook's pick, read from the store: the same presence
  /// rule the recipe screens use, never a second implementation.
  Future<AvailabilityResult> _evaluate(
    RecipeDetail recipe,
    String? methodKey,
  ) async {
    final owned = await store.ownedEquipmentCodes();
    final statuses = await store.statusesOf(<String>[
      for (final line in recipe.lines) line.ingredientCode,
    ]);
    return availabilityService.evaluate(
      recipe: recipe,
      methodKey: methodKey,
      ownedEquipmentCodes: owned,
      statuses: statuses,
    );
  }

  Future<RecipeDetail> _requireRecipe(String slug) async {
    final recipe = await store.loadRecipe(slug);
    if (recipe == null) {
      throw const EngineException(EngineError.recipeNotFound);
    }
    return recipe;
  }

  Future<GuidedSession> _requireSession(String sessionId) async {
    final session = await store.loadSession(sessionId);
    if (session == null) {
      throw const EngineException(EngineError.noActiveSession);
    }
    return session;
  }

  void _requireActive(GuidedSession session) {
    if (session.status.isTerminal) {
      throw const EngineException(EngineError.sessionNotActive);
    }
  }

  TimerState _timerFor(GuidedSession session, DateTime nowUtc) => deriveTimer(
    timerStartedAtUtc: session.timerStartedAtUtc,
    timerDurationSeconds: session.timerDurationSeconds,
    nowUtc: nowUtc,
    lastSeenAtUtc: session.lastSeenAtUtc,
    inMemoryLastSeenUtc: _lastObserved[session.id],
  );

  void _observe(String sessionId, DateTime nowUtc) {
    final previous = _lastObserved[sessionId];
    if (previous == null || nowUtc.isAfter(previous)) {
      _lastObserved[sessionId] = nowUtc;
    }
  }

  static DateTime _newest(List<DateTime?> candidates) {
    DateTime? newest;
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      if (newest == null || candidate.isAfter(newest)) {
        newest = candidate;
      }
    }
    return newest ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
