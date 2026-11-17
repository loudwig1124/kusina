/// Guide models (`docs/09` §11.1), built on the Phase A domain models.
///
/// Pure Dart: no Flutter, no sqflite, no I/O. The recipe, step, method, stock
/// and availability types are the ones already shipped in `lib/domain/models`
/// and `lib/domain/rules` — this file adds only the session, timer, review and
/// result shapes the engine needs.
library;

import '../models/recipe.dart';
import '../models/stock.dart';
import '../rules/availability_service.dart';

/// Session lifecycle (`docs/09` §5.1). At most one `inProgress` at a time.
enum SessionStatus {
  inProgress('in_progress'),
  completed('completed'),
  abandoned('abandoned');

  const SessionStatus(this.wireCode);

  final String wireCode;

  bool get isTerminal => this != SessionStatus.inProgress;
}

/// Timer phases (`docs/09` §6.3). Derived from absolute instants only.
enum TimerPhase { idle, running, done, overrun }

/// The three review choices (`docs/06` §3.4). Exactly three; the labels are
/// locked copy.
enum CompletionChoice {
  didntUse("Didn't use"),
  usedIt('Used it'),
  usedItUp('Used it up');

  const CompletionChoice(this.label);

  final String label;
}

/// Engine-level error taxonomy (`docs/09` §5.6); the UI maps codes to copy.
enum EngineError {
  recipeNotFound,
  seedInvalid,
  activeSessionExists,
  availabilityBlocked,
  methodChoiceRequired,
  noActiveSession,
  sessionNotActive,
  stepOutOfRange,
  alreadyAtReview,
  completionIncomplete,
  invalidCompletionLine,
  abandonNotConfirmed,
  timerNotAvailable,
  timerAlreadyRunning,
  seedMissing,
}

class EngineException implements Exception {
  const EngineException(this.code, [this.detail]);

  final EngineError code;
  final String? detail;

  @override
  String toString() =>
      'EngineException(${code.name}${detail == null ? '' : ': $detail'})';
}

/// The resolved text/timer/sprite of one step on the pinned path. Stored in the
/// session so later content edits cannot rewrite a running cook.
class StepSnapshot {
  const StepSnapshot({
    required this.instruction,
    required this.detail,
    required this.durationSeconds,
    required this.spriteKey,
    required this.equipmentCode,
    required this.isVariant,
    required this.variantMethodKey,
    required this.kind,
    required this.ingredientCodes,
    required this.caution,
    required this.variantGroup,
  });

  final String instruction;
  final String? detail;
  final int? durationSeconds;
  final String spriteKey;
  final String? equipmentCode;
  final bool isVariant;
  final String? variantMethodKey;
  final StepKind kind;
  final List<String> ingredientCodes;
  final String? caution;
  final String? variantGroup;
}

/// One pinned `session_step_choices` row: the appliance and the variant that
/// were chosen at start, plus the resolved snapshot.
class PinnedStep {
  const PinnedStep({
    required this.stepNumber,
    required this.equipmentCode,
    required this.variantMethodKey,
    required this.isVariant,
    required this.snapshot,
  });

  final int stepNumber;
  final String? equipmentCode;

  /// The method whose variant row supplied this implementation, or null.
  final String? variantMethodKey;
  final bool isVariant;
  final StepSnapshot snapshot;
}

/// The frozen path of one session: the cook's method pick and every step's
/// resolved implementation (`docs/09` §4.6).
class EquipmentPath {
  const EquipmentPath({required this.methodKey, required this.steps});

  /// The cook's explicit method pick; null for a single-path dish.
  final String? methodKey;

  /// Step number -> pinned implementation, contiguous `1..N`.
  final Map<int, PinnedStep> steps;

  PinnedStep? step(int stepNumber) => steps[stepNumber];

  int get stepCount => steps.length;
}

/// One cooking session (`docs/09` §5.1). Timers are absolute instants; nothing
/// here holds a countdown.
class GuidedSession {
  const GuidedSession({
    required this.id,
    required this.kitchenId,
    required this.recipeSlug,
    required this.recipeName,
    required this.status,
    required this.currentStepNumber,
    required this.totalSteps,
    required this.startedAtUtc,
    this.lastSeenAtUtc,
    this.completedAtUtc,
    this.timerStartedAtUtc,
    this.timerDurationSeconds,
    required this.startedWithoutAvailability,
    required this.missingCodes,
    required this.path,
  });

  final String id;
  final String kitchenId;
  final String recipeSlug;
  final String recipeName;
  final SessionStatus status;

  /// `1..N`; `N+1` is the review sentinel.
  final int currentStepNumber;
  final int totalSteps;
  final DateTime startedAtUtc;
  final DateTime? lastSeenAtUtc;
  final DateTime? completedAtUtc;
  final DateTime? timerStartedAtUtc;
  final int? timerDurationSeconds;

  /// True only when a blocked dish was started through Guide anyway.
  final bool startedWithoutAvailability;

  /// Frozen stable codes (`equipment:air_fryer`, `ingredient:bay_leaf`, ...).
  final List<String> missingCodes;
  final EquipmentPath path;

  bool get isReview => currentStepNumber == totalSteps + 1;
  bool get isActive => status == SessionStatus.inProgress;

  GuidedSession copyWith({
    SessionStatus? status,
    int? currentStepNumber,
    DateTime? lastSeenAtUtc,
    DateTime? completedAtUtc,
    DateTime? timerStartedAtUtc,
    int? timerDurationSeconds,
    bool clearTimer = false,
  }) {
    return GuidedSession(
      id: id,
      kitchenId: kitchenId,
      recipeSlug: recipeSlug,
      recipeName: recipeName,
      status: status ?? this.status,
      currentStepNumber: currentStepNumber ?? this.currentStepNumber,
      totalSteps: totalSteps,
      startedAtUtc: startedAtUtc,
      lastSeenAtUtc: lastSeenAtUtc ?? this.lastSeenAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      timerStartedAtUtc: clearTimer
          ? null
          : (timerStartedAtUtc ?? this.timerStartedAtUtc),
      timerDurationSeconds: clearTimer
          ? null
          : (timerDurationSeconds ?? this.timerDurationSeconds),
      startedWithoutAvailability: startedWithoutAvailability,
      missingCodes: missingCodes,
      path: path,
    );
  }
}

/// Derived timer state (`docs/09` §6.2). Remaining is never persisted.
class TimerState {
  const TimerState({
    required this.phase,
    required this.remaining,
    required this.elapsed,
    this.overdue,
    this.clockSkewDetected = false,
  });

  const TimerState.idle()
    : phase = TimerPhase.idle,
      remaining = Duration.zero,
      elapsed = Duration.zero,
      overdue = null,
      clockSkewDetected = false;

  final TimerPhase phase;
  final Duration remaining;
  final Duration elapsed;

  /// Null when idle/running; zero at `done`; positive at `overrun`.
  final Duration? overdue;
  final bool clockSkewDetected;

  bool get isRunning => phase == TimerPhase.running;
  bool get hasEnded => phase == TimerPhase.done || phase == TimerPhase.overrun;
}

/// What the guide renders for the current position (`docs/09` §11.1).
class StepView {
  const StepView({
    required this.stepNumber,
    required this.totalSteps,
    required this.isReview,
    required this.kind,
    required this.instruction,
    required this.detail,
    required this.caution,
    required this.spriteKey,
    required this.equipmentCode,
    required this.ingredientCodes,
    required this.isVariant,
    required this.timer,
    required this.progressFraction,
  });

  final int stepNumber;
  final int totalSteps;
  final bool isReview;
  final StepKind kind;
  final String instruction;
  final String? detail;
  final String? caution;
  final String spriteKey;
  final String? equipmentCode;
  final List<String> ingredientCodes;
  final bool isVariant;
  final TimerState timer;
  final double progressFraction;

  int get progressPercent => (progressFraction * 100).floor();
}

/// One review line (`docs/09` §8). `status` is the snapshot shown to the cook;
/// completion re-reads the live status before writing.
class CompletionLine {
  const CompletionLine({
    required this.ingredientCode,
    required this.ingredientName,
    required this.isRequired,
    required this.status,
    required this.choice,
    required this.allowedChoices,
    required this.restockToHave,
  });

  final String ingredientCode;
  final String ingredientName;
  final bool isRequired;
  final StockStatus status;
  final CompletionChoice choice;
  final List<CompletionChoice> allowedChoices;

  /// The review "I have it" correction, applied before the usage transition.
  final bool restockToHave;

  CompletionLine copyWith({CompletionChoice? choice, bool? restockToHave}) {
    return CompletionLine(
      ingredientCode: ingredientCode,
      ingredientName: ingredientName,
      isRequired: isRequired,
      status: status,
      choice: choice ?? this.choice,
      allowedChoices: allowedChoices,
      restockToHave: restockToHave ?? this.restockToHave,
    );
  }

  /// The status the usage transition will actually start from: the restock
  /// correction moves the line to `have` first (`docs/09` §8.4).
  StockStatus get effectiveStatus =>
      restockToHave && status != StockStatus.have ? StockStatus.have : status;

  /// Choices that are legal after the restock correction.
  List<CompletionChoice> get effectiveAllowedChoices {
    final effective = effectiveStatus;
    return <CompletionChoice>[
      CompletionChoice.didntUse,
      if (effective != StockStatus.out) CompletionChoice.usedIt,
      CompletionChoice.usedItUp,
    ];
  }

  /// True when this choice would write nothing for the shown status (the UI says
  /// why: "already low", "already out").
  bool get isNoOp => completionTransitionsFor(
    ingredientCode: ingredientCode,
    current: restockToHave ? StockStatus.have : status,
    choice: choice,
  ).isEmpty;
}

/// One stock write the completion produces (`docs/09` §8.4).
class StockTransition {
  const StockTransition({
    required this.ingredientCode,
    required this.from,
    required this.to,
    required this.reason,
    required this.sessionLinked,
  });

  final String ingredientCode;
  final StockStatus from;
  final StockStatus to;
  final StockReason reason;

  /// True for `used_some` / `used_up`; false for the review `restock`.
  final bool sessionLinked;

  @override
  String toString() =>
      '$ingredientCode ${from.wireCode}->${to.wireCode} '
      '(${reason.wireCode}${sessionLinked ? ', linked' : ''})';
}

/// Result of `start()` (`docs/09` §5.3).
class StartResult {
  const StartResult({
    this.session,
    this.activeSession,
    this.blockedBy,
    this.error,
  });

  final GuidedSession? session;
  final GuidedSession? activeSession;
  final AvailabilityResult? blockedBy;
  final EngineError? error;

  bool get started => session != null;
  bool get hasActiveSession => activeSession != null;
  bool get isBlocked => blockedBy != null;
}

/// Result of `onResume()` (`docs/09` §5.4). Read-only.
class ResumeInfo {
  const ResumeInfo({
    required this.session,
    required this.step,
    required this.isReview,
    required this.timer,
    required this.awaySince,
    required this.timerFinishedAgo,
    required this.stale,
    required this.resumeCopy,
  });

  final GuidedSession session;
  final StepView? step;
  final bool isReview;
  final TimerState timer;
  final Duration awaySince;
  final Duration? timerFinishedAgo;

  /// Started more than 24 h ago; the engine never auto-abandons.
  final bool stale;
  final String resumeCopy;
}

enum CompletionOutcome { completed, alreadyCompleted, rejected }

/// Result of `complete()` (`docs/09` §11.1).
class CompletionResult {
  const CompletionResult({
    required this.outcome,
    required this.lines,
    required this.usedItCount,
    required this.usedItUpCount,
    required this.didntUseCount,
    required this.restockCorrections,
    required this.eventsWritten,
    this.error,
  });

  final CompletionOutcome outcome;
  final List<CompletionLine> lines;
  final int usedItCount;
  final int usedItUpCount;
  final int didntUseCount;
  final int restockCorrections;
  final int eventsWritten;
  final EngineError? error;

  bool get isCompleted => outcome == CompletionOutcome.completed;
  bool get isAlreadyCompleted => outcome == CompletionOutcome.alreadyCompleted;
  bool get isRejected => outcome == CompletionOutcome.rejected;
}

/// The three-choice mapping for one line (`docs/09` §8.3/§8.4).
///
/// Returns 0-2 chained transitions: an optional `restock` correction first, then
/// the usage transition. `out` + `usedIt` is invalid and returns an empty list;
/// callers reject it before calling here.
List<StockTransition> completionTransitionsFor({
  required String ingredientCode,
  required StockStatus current,
  required CompletionChoice choice,
  bool restockToHave = false,
}) {
  final transitions = <StockTransition>[];
  var status = current;
  if (restockToHave && status != StockStatus.have) {
    transitions.add(
      StockTransition(
        ingredientCode: ingredientCode,
        from: status,
        to: StockStatus.have,
        reason: StockReason.restock,
        sessionLinked: false,
      ),
    );
    status = StockStatus.have;
  }
  switch ((status, choice)) {
    case (StockStatus.have, CompletionChoice.usedIt):
      transitions.add(
        StockTransition(
          ingredientCode: ingredientCode,
          from: StockStatus.have,
          to: StockStatus.low,
          reason: StockReason.usedSome,
          sessionLinked: true,
        ),
      );
    case (StockStatus.unknown, CompletionChoice.usedIt):
      transitions.add(
        StockTransition(
          ingredientCode: ingredientCode,
          from: StockStatus.unknown,
          to: StockStatus.low,
          reason: StockReason.usedSome,
          sessionLinked: true,
        ),
      );
    case (StockStatus.have, CompletionChoice.usedItUp):
      transitions.add(
        StockTransition(
          ingredientCode: ingredientCode,
          from: StockStatus.have,
          to: StockStatus.out,
          reason: StockReason.usedUp,
          sessionLinked: true,
        ),
      );
    case (StockStatus.low, CompletionChoice.usedItUp):
      transitions.add(
        StockTransition(
          ingredientCode: ingredientCode,
          from: StockStatus.low,
          to: StockStatus.out,
          reason: StockReason.usedUp,
          sessionLinked: true,
        ),
      );
    case (StockStatus.unknown, CompletionChoice.usedItUp):
      transitions.add(
        StockTransition(
          ingredientCode: ingredientCode,
          from: StockStatus.unknown,
          to: StockStatus.out,
          reason: StockReason.usedUp,
          sessionLinked: true,
        ),
      );
    default:
      break; // low+usedIt, out+usedItUp, out+usedIt, any didntUse: no usage event
  }
  return List<StockTransition>.unmodifiable(transitions);
}
