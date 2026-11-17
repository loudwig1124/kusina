/// Drives the guide and usage-review screens (`docs/09` §5-§8, `docs/07` §9).
///
/// A thin UI shell over the pure engine: it owns the screen state (loaded step,
/// ticker, review selections, keep-awake) and never decides a rule itself.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/guide/guide_engine.dart';
import '../../domain/guide/guide_models.dart';
import '../../domain/models/recipe.dart';

/// The route segment the recipe detail screen uses to ask for a start; it is
/// not a real session id.
const String startSessionId = 'preview';

class GuideController extends ChangeNotifier {
  GuideController({
    required this.engine,
    DateTime Function()? clock,
    this.onResetSessions,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final GuidedCookingEngine engine;
  final DateTime Function() _clock;
  final Future<void> Function()? onResetSessions;

  GuidedSession? _session;
  StepView? _step;
  TimerState _timer = const TimerState.idle();
  RecipeDetail? _recipe;
  String? _message;
  EngineError? _error;
  bool _loading = false;
  bool _busy = false;
  Timer? _ticker;
  bool _keepAwake = false;
  ResumeInfo? _resumeInfo;

  GuidedSession? get session => _session;
  StepView? get stepView => _step;
  TimerState get timer => _timer;
  RecipeDetail? get recipe => _recipe;
  String? get message => _message;
  EngineError? get error => _error;
  bool get isLoading => _loading;
  bool get isBusy => _busy;

  /// Cached so the Settings route, the resume card and the recipe detail can
  /// guard on it without awaiting.
  bool get hasActiveSession => _session?.isActive ?? false;

  /// The active session, if one exists (drives the Cook Now resume card).
  GuidedSession? get activeSession =>
      _session?.isActive == true ? _session : null;

  /// The engine's resume sentence after the app came back (banner copy).
  String? get resumeCopy => _resumeInfo?.resumeCopy;

  /// True while the guide asked the platform to keep the screen awake.
  bool get keepAwakeRequested => _keepAwake;

  String get methodLabel {
    final methodKey = _session?.path.methodKey;
    if (methodKey == null) {
      return 'Single method';
    }
    for (final method in _recipe?.methods ?? const <RecipeMethod>[]) {
      if (method.key == methodKey) {
        return '${method.label} method';
      }
    }
    return methodKey;
  }

  /// Opens an existing session, or starts one for [startSessionId].
  ///
  /// Returns true when the session is at the review sentinel, so the caller can
  /// route to the review instead of a step.
  Future<bool> open({
    required String sessionId,
    String? recipeSlug,
    String? methodKey,
    bool guideAnyway = false,
  }) async {
    _loading = true;
    _error = null;
    _message = null;
    notifyListeners();
    try {
      final nowUtc = _clock();
      if (sessionId == startSessionId) {
        final active = await engine.activeSession();
        if (active != null) {
          _session = active;
        } else if (recipeSlug == null) {
          _error = EngineError.recipeNotFound;
        } else {
          final result = await engine.start(
            recipeSlug: recipeSlug,
            methodKey: methodKey,
            guideAnyway: guideAnyway,
            nowUtc: nowUtc,
          );
          _session = result.session ?? result.activeSession;
          if (_session == null) {
            _error = result.error ?? EngineError.availabilityBlocked;
            _message = result.blockedBy == null
                ? null
                : 'Still blocked: ${result.blockedBy!.missingCodes.join(', ')}';
          }
        }
      } else {
        _session = await engine.session(sessionId);
        _session ??= await engine.activeSession();
        if (_session == null) {
          _error = EngineError.noActiveSession;
        }
      }

      if (_session != null) {
        _recipe = await engine.recipe(_session!.recipeSlug);
        await _refreshStep();
      }
      _loading = false;
      notifyListeners();
      return _session?.isReview ?? false;
    } on EngineException catch (error) {
      _error = error.code;
      _message = error.detail;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Loads the active session from the store without starting anything.
  ///
  /// Called at app bootstrap, after completing/abandoning and when the home
  /// screen appears, so a relaunch on SQLite shows the resume card.
  Future<void> refreshActiveSession() async {
    try {
      final active = await engine.activeSession();
      if (active == null) {
        if (_session != null && _session!.isActive) {
          _session = null;
          _step = null;
          _timer = const TimerState.idle();
          _recipe = null;
          _syncTicker();
          _syncKeepAwake();
          notifyListeners();
        }
        return;
      }
      _session = active;
      _recipe = await engine.recipe(active.recipeSlug);
      if (active.isReview) {
        _step = null;
        _timer = const TimerState.idle();
      } else {
        _step = await engine.currentStep(
          sessionId: active.id,
          nowUtc: _clock(),
        );
        _timer = await engine.timerState(
          sessionId: active.id,
          nowUtc: _clock(),
        );
      }
      _error = null;
      _syncTicker();
      _syncKeepAwake();
      notifyListeners();
    } on EngineException catch (error) {
      _error = error.code;
      notifyListeners();
    }
  }

  /// Reloads the current step and timer from the engine (no writes).
  Future<void> refresh() async {
    if (_session == null) {
      return;
    }
    _session = await engine.session(_session!.id);
    if (_session == null) {
      _error = EngineError.noActiveSession;
      notifyListeners();
      return;
    }
    await _refreshStep();
    notifyListeners();
  }

  Future<void> advance() async {
    final session = _session;
    if (session == null || _busy || session.isReview) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final view = await engine.advance(
        sessionId: session.id,
        nowUtc: _clock(),
      );
      _session = await engine.session(session.id);
      _step = view.isReview ? null : view;
      _timer = view.timer;
      _message = null;
      _syncTicker();
    } on EngineException catch (error) {
      _error = error.code;
      _message = error.detail;
    } finally {
      _busy = false;
      _syncKeepAwake();
      notifyListeners();
    }
  }

  Future<void> startTimer() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      _timer = await engine.startTimer(sessionId: session.id, nowUtc: _clock());
      _session = await engine.session(session.id);
      _syncTicker();
    } on EngineException catch (error) {
      _error = error.code;
      _message = switch (error.code) {
        EngineError.timerAlreadyRunning => 'The timer is already running.',
        EngineError.timerNotAvailable => 'No timer on this step.',
        _ => error.detail ?? 'The timer is not available.',
      };
    }
    _syncKeepAwake();
    notifyListeners();
  }

  Future<void> clearTimer() async {
    final session = _session;
    if (session == null) {
      return;
    }
    await engine.clearTimer(sessionId: session.id);
    _timer = const TimerState.idle();
    _syncTicker();
    _syncKeepAwake();
    notifyListeners();
  }

  Future<GuidedSession?> abandon() async {
    final session = _session;
    if (session == null) {
      return null;
    }
    final abandoned = await engine.abandon(
      sessionId: session.id,
      confirmed: true,
      nowUtc: _clock(),
    );
    _session = null;
    _step = null;
    _timer = const TimerState.idle();
    _syncTicker();
    _syncKeepAwake();
    notifyListeners();
    return abandoned;
  }

  /// Loads the review lines (defaults computed by the engine) for the sentinel.
  Future<List<CompletionLine>> loadReview() async {
    final session = _session;
    if (session == null) {
      return const <CompletionLine>[];
    }
    if (!session.isReview) {
      throw const EngineException(EngineError.completionIncomplete);
    }
    return engine.review(sessionId: session.id);
  }

  /// Confirms the review. Idempotent: a second confirm returns alreadyCompleted
  /// and writes nothing.
  Future<CompletionResult?> complete(List<CompletionLine> lines) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await engine.complete(
        sessionId: session.id,
        lines: lines,
        nowUtc: _clock(),
      );
      if (result.isCompleted || result.isAlreadyCompleted) {
        _session = await engine.session(session.id);
        _message = result.isAlreadyCompleted
            ? 'Already saved.'
            : 'Saved. ${result.eventsWritten} stock '
                  '${result.eventsWritten == 1 ? 'change' : 'changes'}.';
      } else {
        _error = result.error ?? EngineError.invalidCompletionLine;
        _message = 'One choice no longer applies — review and confirm again.';
      }
      return result;
    } on EngineException catch (error) {
      _error = error.code;
      _message = error.detail;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// The app went to the background: persist `last_seen_at` and release the
  /// wake lock (`docs/09` §6.4, `docs/07` §9.6).
  Future<void> onPause() async {
    final session = _session;
    if (session != null && session.isActive) {
      try {
        await engine.onPause(sessionId: session.id, nowUtc: _clock());
      } on EngineException {
        // A terminal or missing session has nothing to persist.
      }
    }
    _releaseKeepAwake();
  }

  /// The app came back: derive the resume copy and mark the session seen.
  ///
  /// Read-only first (`engine.onResume`), then `markSeen` writes `last_seen_at`
  /// so the next resume sentence is relative to this return.
  Future<void> onResumeFromBackground() async {
    final session = _session;
    if (session == null || !session.isActive) {
      return;
    }
    try {
      _resumeInfo = await engine.onResume(
        sessionId: session.id,
        nowUtc: _clock(),
      );
      await engine.markSeen(sessionId: session.id, nowUtc: _clock());
      _session = await engine.session(session.id) ?? _session;
      if (session.isReview) {
        _step = null;
      } else {
        _step = await engine.currentStep(
          sessionId: session.id,
          nowUtc: _clock(),
        );
      }
      _timer = await engine.timerState(sessionId: session.id, nowUtc: _clock());
      _syncTicker();
      _syncKeepAwake();
    } on EngineException catch (error) {
      _error = error.code;
    }
    notifyListeners();
  }

  /// Dismisses the resume banner (the cook read it).
  void dismissResumeBanner() {
    if (_resumeInfo == null) {
      return;
    }
    _resumeInfo = null;
    notifyListeners();
  }

  /// Drops every session (Reset demo data). Stock resets belong to the seed
  /// loader; this only clears the guide's own store.
  Future<void> resetSessions() async {
    await onResetSessions?.call();
    _session = null;
    _step = null;
    _timer = const TimerState.idle();
    _recipe = null;
    _error = null;
    _message = null;
    _syncTicker();
    _syncKeepAwake();
    notifyListeners();
  }

  /// Marks the session seen (lifecycle pause, leaving the guide).
  Future<void> markSeen() async {
    final session = _session;
    if (session == null || session.status.isTerminal) {
      return;
    }
    await engine.markSeen(sessionId: session.id, nowUtc: _clock());
  }

  /// The guide keeps the screen awake only while a timer is running
  /// (`docs/09` §6.6). Fire-and-forget: a missing or slow platform channel must
  /// never delay the countdown or a rebuild.
  void _syncKeepAwake() {
    final shouldStayAwake = _timer.phase == TimerPhase.running;
    if (shouldStayAwake == _keepAwake) {
      return;
    }
    _keepAwake = shouldStayAwake;
    try {
      final call = shouldStayAwake
          ? WakelockPlus.enable()
          : WakelockPlus.disable();
      call.catchError((Object _) {});
    } catch (_) {
      // Platform channel unavailable (widget tests / unsupported host): the
      // timer stays correct; only the convenience wake lock is skipped.
    }
  }

  void _syncTicker() {
    final shouldTick = _timer.phase == TimerPhase.running;
    if (shouldTick && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (!shouldTick) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _tick() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      _timer = await engine.timerState(sessionId: session.id, nowUtc: _clock());
      if (_timer.phase != TimerPhase.running) {
        _syncTicker();
        _syncKeepAwake();
      }
      notifyListeners();
    } on EngineException {
      _syncTicker();
    }
  }

  Future<void> _refreshStep() async {
    final session = _session;
    if (session == null || session.isReview) {
      _step = null;
      _timer = const TimerState.idle();
      return;
    }
    _step = await engine.currentStep(sessionId: session.id, nowUtc: _clock());
    _timer = await engine.timerState(sessionId: session.id, nowUtc: _clock());
    _syncTicker();
    _syncKeepAwake();
  }

  /// Cancels the display ticker while no guide screen is mounted; a running
  /// timer re-derives from its absolute start when the guide reopens.
  void pauseTicking() {
    _ticker?.cancel();
    _ticker = null;
    // Leaving the guide drops the wake lock and the stale banner.
    _releaseKeepAwake();
    _resumeInfo = null;
  }

  void _releaseKeepAwake() {
    if (!_keepAwake) {
      return;
    }
    _keepAwake = false;
    try {
      WakelockPlus.disable().catchError((Object _) {});
    } catch (_) {
      // Platform channel unavailable (tests / unsupported host).
    }
  }

  /// Clearing the transient message keeps the toast single-shot.
  void clearMessage() {
    if (_message == null && _error == null) {
      return;
    }
    _message = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    if (_keepAwake) {
      WakelockPlus.disable().catchError((Object _) {});
    }
    super.dispose();
  }
}

/// The three review choices in display order (`docs/07` §8).
const List<CompletionChoice> reviewChoices = <CompletionChoice>[
  CompletionChoice.didntUse,
  CompletionChoice.usedIt,
  CompletionChoice.usedItUp,
];
