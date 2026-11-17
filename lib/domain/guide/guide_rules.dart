/// Pure guide rules (`docs/09` §11.2): timer derivation, progress, the review
/// transition table, method pinning and the copy the engine owns.
///
/// No state, no clock reads, no Flutter. Every function takes `nowUtc`.
library;

import '../models/recipe.dart';
import '../models/stock.dart';
import 'guide_models.dart';

/// Derives the timer from absolute instants (`docs/09` §6.2).
///
/// [inMemoryLastSeenUtc] is the newest instant the guide observed while
/// foreground; it is what distinguishes `done` (the deadline was crossed on
/// screen) from `overrun` (it ended while the cook was away).
TimerState deriveTimer({
  required DateTime? timerStartedAtUtc,
  required int? timerDurationSeconds,
  required DateTime nowUtc,
  required DateTime? lastSeenAtUtc,
  DateTime? inMemoryLastSeenUtc,
}) {
  if (timerStartedAtUtc == null ||
      timerDurationSeconds == null ||
      timerDurationSeconds <= 0) {
    return const TimerState.idle();
  }
  final duration = Duration(seconds: timerDurationSeconds);
  if (nowUtc.isBefore(timerStartedAtUtc)) {
    return TimerState(
      phase: TimerPhase.running,
      remaining: duration,
      elapsed: Duration.zero,
      clockSkewDetected: true,
    );
  }
  final deadline = timerStartedAtUtc.add(duration);
  final raw = deadline.difference(nowUtc);
  if (raw > Duration.zero) {
    final elapsed = nowUtc.difference(timerStartedAtUtc);
    return TimerState(
      phase: TimerPhase.running,
      remaining: raw,
      elapsed: elapsed > duration ? duration : elapsed,
    );
  }
  final endedAgo = nowUtc.difference(deadline);
  final seenCandidates = <DateTime>[
    ?lastSeenAtUtc,
    ?inMemoryLastSeenUtc,
    timerStartedAtUtc,
  ];
  final lastSeen = seenCandidates.reduce((a, b) => a.isAfter(b) ? a : b);
  return TimerState(
    phase: lastSeen.isBefore(deadline) ? TimerPhase.overrun : TimerPhase.done,
    remaining: Duration.zero,
    elapsed: duration,
    overdue: endedAgo,
  );
}

/// `docs/09` §8.1: `Used it` is disabled for `out`, everything else is allowed.
bool isChoiceAllowed(StockStatus status, CompletionChoice choice) {
  if (choice == CompletionChoice.didntUse) {
    return true;
  }
  if (status == StockStatus.out) {
    return choice == CompletionChoice.usedItUp;
  }
  return true;
}

/// Exactly three choices, or two when the line is already `out`.
List<CompletionChoice> allowedChoicesFor(StockStatus status) {
  return <CompletionChoice>[
    CompletionChoice.didntUse,
    if (status != StockStatus.out) CompletionChoice.usedIt,
    CompletionChoice.usedItUp,
  ];
}

/// The default choice for a line (`docs/09` §8.2): required `have`/`low` are
/// pre-ticked `usedIt`; `unknown`, `out` and every optional line stay
/// `didntUse`. Defaults are presentation only; nothing is written until
/// completion.
CompletionChoice defaultChoiceFor({
  required StockStatus status,
  required bool isRequired,
}) {
  if (!isRequired) {
    return CompletionChoice.didntUse;
  }
  if (status == StockStatus.have || status == StockStatus.low) {
    return CompletionChoice.usedIt;
  }
  return CompletionChoice.didntUse;
}

/// Builds the review lines for a recipe from the current statuses.
List<CompletionLine> defaultCompletionLines(
  RecipeDetail recipe,
  Map<String, StockStatus> statuses,
) {
  return <CompletionLine>[
    for (final line in recipe.lines)
      CompletionLine(
        ingredientCode: line.ingredientCode,
        ingredientName: line.name,
        isRequired: !line.isOptional,
        status: statuses[line.ingredientCode] ?? StockStatus.unknown,
        choice: defaultChoiceFor(
          status: statuses[line.ingredientCode] ?? StockStatus.unknown,
          isRequired: !line.isOptional,
        ),
        allowedChoices: allowedChoicesFor(
          statuses[line.ingredientCode] ?? StockStatus.unknown,
        ),
        restockToHave: false,
      ),
  ];
}

/// Completed steps for the persisted index (`docs/09` §7.1).
int completedSteps(int currentStepNumber, int totalSteps) {
  final completed = currentStepNumber - 1;
  if (completed < 0) {
    return 0;
  }
  if (completed > totalSteps) {
    return totalSteps;
  }
  return completed;
}

/// Progress fraction `(k-1)/N`; 100% only at the review sentinel.
double progressFraction(int currentStepNumber, int totalSteps) {
  if (totalSteps <= 0) {
    return 0;
  }
  return completedSteps(currentStepNumber, totalSteps) / totalSteps;
}

int progressPercent(int currentStepNumber, int totalSteps) =>
    (progressFraction(currentStepNumber, totalSteps) * 100).floor();

/// Pins the cook's method choice into one snapshot per step (`docs/09` §4.2).
///
/// Throws [EngineException] `methodChoiceRequired` when a method dish is asked
/// for without a pick, and `seedInvalid` when a step cannot resolve on that
/// path (a content error, never a silent fallback to the other method).
EquipmentPath planPath(RecipeDetail recipe, String? methodKey) {
  if (recipe.hasMethodChoice) {
    if (methodKey == null) {
      throw const EngineException(
        EngineError.methodChoiceRequired,
        'the cook must pick a method',
      );
    }
    if (recipe.methodFor(methodKey) == null) {
      throw EngineException(
        EngineError.methodChoiceRequired,
        'unknown method "$methodKey"',
      );
    }
  } else if (methodKey != null) {
    throw EngineException(
      EngineError.methodChoiceRequired,
      '${recipe.slug} has a single path',
    );
  }
  final method = recipe.methodFor(methodKey);
  final pinned = <int, PinnedStep>{};
  for (final step in recipe.steps) {
    final implementation = step.resolveFor(method);
    if (implementation == null) {
      throw EngineException(
        EngineError.seedInvalid,
        '${recipe.slug} step ${step.stepNumber} cannot resolve for '
        'method "$methodKey"',
      );
    }
    pinned[step.stepNumber] = PinnedStep(
      stepNumber: step.stepNumber,
      equipmentCode: implementation.equipmentCode,
      variantMethodKey: implementation.isVariant
          ? implementation.variant?.methodKey
          : null,
      isVariant: implementation.isVariant,
      snapshot: StepSnapshot(
        instruction: implementation.instruction,
        detail: implementation.detail,
        durationSeconds:
            implementation.durationSeconds == null ||
                implementation.durationSeconds! <= 0
            ? null
            : implementation.durationSeconds,
        spriteKey: implementation.spriteKey,
        equipmentCode: implementation.equipmentCode,
        isVariant: implementation.isVariant,
        variantMethodKey: implementation.variant?.methodKey,
        kind: step.kind,
        ingredientCodes: step.ingredientRefs,
        caution: step.caution,
        variantGroup: step.variantGroup,
      ),
    );
  }
  return EquipmentPath(methodKey: methodKey, steps: pinned);
}

/// The view for the session's current position. At the review sentinel this
/// returns a review view (`isReview == true`) instead of throwing.
StepView stepViewFor(
  GuidedSession session, {
  required DateTime nowUtc,
  DateTime? inMemoryLastSeenUtc,
}) {
  final timer = deriveTimer(
    timerStartedAtUtc: session.timerStartedAtUtc,
    timerDurationSeconds: session.timerDurationSeconds,
    nowUtc: nowUtc,
    lastSeenAtUtc: session.lastSeenAtUtc,
    inMemoryLastSeenUtc: inMemoryLastSeenUtc,
  );
  final progress = progressFraction(
    session.currentStepNumber,
    session.totalSteps,
  );
  if (session.isReview) {
    return StepView(
      stepNumber: session.currentStepNumber,
      totalSteps: session.totalSteps,
      isReview: true,
      kind: StepKind.finish,
      instruction: 'Review what the dish used.',
      detail: null,
      caution: null,
      spriteKey: 'step_finish_none',
      equipmentCode: null,
      ingredientCodes: const <String>[],
      isVariant: false,
      timer: timer,
      progressFraction: progress,
    );
  }
  final pinned = session.path.step(session.currentStepNumber);
  if (pinned == null) {
    throw EngineException(
      EngineError.seedMissing,
      'no pinned row for step ${session.currentStepNumber}',
    );
  }
  final snapshot = pinned.snapshot;
  return StepView(
    stepNumber: session.currentStepNumber,
    totalSteps: session.totalSteps,
    isReview: false,
    kind: snapshot.kind,
    instruction: snapshot.instruction,
    detail: snapshot.detail,
    caution: snapshot.caution,
    spriteKey: snapshot.spriteKey,
    equipmentCode: pinned.equipmentCode,
    ingredientCodes: snapshot.ingredientCodes,
    isVariant: pinned.isVariant,
    timer: timer,
    progressFraction: progress,
  );
}

/// `mm:ss` for the ring centre.
String formatCountdown(Duration remaining) {
  final safe = remaining.isNegative ? Duration.zero : remaining;
  final minutes = safe.inMinutes;
  final seconds = safe.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Largest unit, rounded down (`docs/09` §6.3).
String formatAway(Duration away) {
  if (away < const Duration(minutes: 1)) {
    return 'less than a minute';
  }
  if (away < const Duration(hours: 1)) {
    return '${away.inMinutes} min';
  }
  if (away < const Duration(hours: 24)) {
    return '${away.inHours} hr';
  }
  return 'more than a day';
}

/// The engine's copy for a timer state (`docs/09` §6.3). Single source of truth.
String timerCopy(TimerState timer) {
  return switch (timer.phase) {
    TimerPhase.idle => '',
    TimerPhase.running => '${formatCountdown(timer.remaining)} left',
    TimerPhase.done => 'Timer done.',
    TimerPhase.overrun =>
      'Timer finished ${formatAway(timer.overdue ?? Duration.zero)} ago.',
  };
}

/// Resume copy (`docs/09` §6.3). Composed here, never by the UI.
String resumeCopy({
  required GuidedSession session,
  required TimerState timer,
  required Duration awaySince,
}) {
  if (session.isReview) {
    return 'Welcome back. Review what the dish used.';
  }
  if (timer.phase == TimerPhase.overrun) {
    final ago = formatAway(timer.overdue ?? Duration.zero);
    return 'You were away ${formatAway(awaySince)}. '
        'The timer finished $ago ago.';
  }
  return 'Welcome back. Step ${session.currentStepNumber} of '
      '${session.totalSteps}.';
}

/// Loader lint (`docs/09` §2.4, L1-L13 subset the engine depends on). Returns
/// the problems found; an empty list means the recipe is safe to start.
List<String> lintRecipe(RecipeDetail recipe) {
  final problems = <String>[];
  if (recipe.steps.isEmpty) {
    problems.add('${recipe.slug}: no steps');
    return problems;
  }
  for (var index = 0; index < recipe.steps.length; index++) {
    final step = recipe.steps[index];
    if (step.stepNumber != index + 1) {
      problems.add('${recipe.slug}: step numbers are not contiguous');
    }
    if (step.instruction.trim().isEmpty) {
      problems.add('${recipe.slug}: step ${step.stepNumber} has no copy');
    }
    final timed =
        step.kind == StepKind.heat ||
        step.kind == StepKind.cook ||
        step.kind == StepKind.wait;
    if (step.kind == StepKind.wait && step.durationSeconds == null) {
      problems.add('${recipe.slug}: wait step ${step.stepNumber} has no timer');
    }
    if (!timed && step.durationSeconds != null) {
      problems.add(
        '${recipe.slug}: ${step.kind.wireCode} step ${step.stepNumber} '
        'must not have a timer',
      );
    }
    if (timed && step.durationSeconds != null && step.durationSeconds! < 0) {
      problems.add(
        '${recipe.slug}: step ${step.stepNumber} duration must not be negative',
      );
    }
    if ((step.kind == StepKind.heat || step.kind == StepKind.cook) &&
        step.equipmentCode == null) {
      problems.add(
        '${recipe.slug}: ${step.kind.wireCode} step ${step.stepNumber} '
        'needs an appliance',
      );
    }
  }
  if (recipe.steps.last.kind != StepKind.finish) {
    problems.add('${recipe.slug}: the last step must be finish');
  }
  if (recipe.steps.where((step) => step.kind == StepKind.finish).length != 1) {
    problems.add('${recipe.slug}: exactly one finish step is required');
  }
  return problems;
}
