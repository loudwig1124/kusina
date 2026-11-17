import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/guide/guide_engine.dart';
import 'package:kusina/domain/guide/guide_models.dart';
import 'package:kusina/domain/guide/guide_rules.dart';
import 'package:kusina/domain/models/stock.dart';

import 'sqlite_harness.dart';

void main() {
  late SqliteHarness harness;

  final now = DateTime.utc(2026, 1, 1, 9);

  setUp(() async {
    harness = await createSqliteHarness();
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('the full Adobo flow runs on SQLite and survives a relaunch', () async {
    final engine = _engineFor(harness);

    // Blocked on the bay leaf: the app sends guideAnyway with the codes.
    final start = await engine.start(
      recipeSlug: 'chicken-adobo',
      methodKey: null,
      guideAnyway: true,
      nowUtc: now,
    );
    final session = start.session!;
    expect(session.startedWithoutAvailability, isTrue);
    expect(session.missingCodes, <String>['ingredient:bay_leaf']);

    // Walk step 1 -> 7 by taps, starting the timer on the 25:00 simmer.
    for (var step = 1; step <= 7; step++) {
      final view = await engine.currentStep(
        sessionId: session.id,
        nowUtc: now.add(Duration(minutes: step)),
      );
      expect(view.stepNumber, step);
      expect(view.progressPercent, ((step - 1) * 100) ~/ 7);
      if (step == 5) {
        final timer = await engine.startTimer(
          sessionId: session.id,
          nowUtc: now.add(const Duration(minutes: 5)),
        );
        expect(formatCountdown(timer.remaining), '25:00');
      }
      if (step < 7) {
        await engine.advance(
          sessionId: session.id,
          nowUtc: now.add(Duration(minutes: step)),
        );
      }
    }
    // The final tap moves to the review sentinel without completing.
    await engine.advance(
      sessionId: session.id,
      nowUtc: now.add(const Duration(minutes: 7)),
    );

    // Kill and relaunch in the review: the session and its path are intact.
    final relaunched = await reopen(harness, seed: true);
    harness = relaunched;
    final resumedEngine = _engineFor(harness);
    final active = await harness.sessions.loadActiveSession();
    expect(active, isNotNull);
    expect(active!.isReview, isTrue);
    expect(active.currentStepNumber, 8);
    expect(active.path.methodKey, isNull);
    expect(active.path.step(5)!.snapshot.durationSeconds, 1500);

    final resume = await resumedEngine.onResume(
      sessionId: active.id,
      nowUtc: now.add(const Duration(hours: 1)),
    );
    expect(resume.isReview, isTrue);
    // Advancing cleared the timer; the columns stay null across the relaunch.
    expect(resume.timer.phase, TimerPhase.idle);
    expect(
      (await harness.db.query('cooking_sessions')).single['timer_started_at'],
      isNull,
    );

    // Review and confirm on the reopened database.
    final lines = await resumedEngine.review(sessionId: active.id);
    final result = await resumedEngine.complete(
      sessionId: active.id,
      lines: lines,
      nowUtc: now.add(const Duration(hours: 1)),
    );
    expect(result.outcome, CompletionOutcome.completed);
    expect(result.eventsWritten, 4, reason: 'four required have lines');

    for (final code in <String>[
      'chicken_thighs',
      'soy_sauce',
      'vinegar',
      'garlic',
    ]) {
      expect(
        await harness.repositories.stock.getStatus(code),
        StockStatus.low,
        reason: '$code has → low',
      );
    }
    expect(
      await harness.repositories.stock.getStatus('bay_leaf'),
      StockStatus.out,
    );
    expect(
      await harness.repositories.stock.getStatus('sugar'),
      StockStatus.have,
    );

    final sessionRow = await harness.db.query('cooking_sessions');
    expect(sessionRow.single['status'], 'completed');
    expect(sessionRow.single['timer_started_at'], isNull);
    final events = await harness.db.query('stock_event');
    expect(events, hasLength(4));
    expect(
      events.every(
        (event) => event['cooking_session_id'] == int.parse(active.id),
      ),
      isTrue,
    );

    // History shows the completed cook on the next launch.
    final history = await harness.sessions.history();
    expect(history, hasLength(1));
    expect(history.single.status, SessionStatus.completed);
    expect(await harness.sessions.loadActiveSession(), isNull);
  });

  test('the Adobo timer round-trips as absolute columns', () async {
    final engine = _engineFor(harness);
    final start = await engine.start(
      recipeSlug: 'chicken-adobo',
      methodKey: null,
      guideAnyway: true,
      nowUtc: now,
    );
    final session = start.session!;
    for (var step = 1; step < 5; step++) {
      await engine.advance(sessionId: session.id, nowUtc: now);
    }
    await engine.startTimer(
      sessionId: session.id,
      nowUtc: now.add(const Duration(minutes: 2)),
    );

    final row = (await harness.db.query('cooking_sessions')).single;
    expect(row['timer_started_at'], '2026-01-01T09:02:00.000Z');
    expect(row['timer_duration_seconds'], 1500);

    // Ten minutes in, the remaining time is derived, not stored.
    final relaunched = await reopen(harness);
    harness = relaunched;
    final timer = await _engineFor(harness).timerState(
      sessionId: session.id,
      nowUtc: now.add(const Duration(minutes: 12)),
    );
    expect(timer.phase, TimerPhase.running);
    expect(formatCountdown(timer.remaining), '15:00');
    expect(
      (await harness.db.query('cooking_sessions'))
          .single['current_step_number'],
      5,
      reason: 'the timer never advances the step',
    );
  });
}

/// A fresh engine over the harness store (models a cold start per call site).
LocalGuidedCookingEngine _engineFor(SqliteHarness harness) =>
    LocalGuidedCookingEngine(store: harness.guideStore);
