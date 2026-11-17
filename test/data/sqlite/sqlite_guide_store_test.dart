import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/guide/guide_engine.dart';
import 'package:kusina/domain/guide/guide_models.dart';
import 'package:kusina/domain/guide/guide_rules.dart';
import 'package:kusina/domain/models/stock.dart';

import 'sqlite_harness.dart';

void main() {
  late SqliteHarness harness;
  late LocalGuidedCookingEngine engine;

  final now = DateTime.utc(2026, 1, 1, 9);

  setUp(() async {
    harness = await createSqliteHarness();
    engine = LocalGuidedCookingEngine(store: harness.guideStore);
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<GuidedSession> startBelly(
    String method, {
    bool guideAnyway = false,
  }) async {
    final result = await engine.start(
      recipeSlug: 'crispy-pork-belly',
      methodKey: method,
      guideAnyway: guideAnyway,
      nowUtc: now,
    );
    expect(result.error, isNull);
    expect(result.session, isNotNull);
    return result.session!;
  }

  group('session rows and the pinned path', () {
    test('start writes the session and one pinned row per step', () async {
      final session = await startBelly('air_fry');

      final rows = await harness.db.query('cooking_sessions');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['id'], int.parse(session.id));
      expect(row['status'], 'in_progress');
      expect(row['current_step_number'], 1);
      expect(row['servings'], 4);
      expect(row['started_without_availability'], 0);
      expect(row['missing_requirements_json'], isNull);
      expect(row['timer_started_at'], isNull);

      final choices = await harness.db.query(
        'session_step_choices',
        where: 'session_id = ?',
        whereArgs: <Object?>[int.parse(session.id)],
        orderBy: 'step_number',
      );
      expect(choices, hasLength(6));
      expect(choices.map((choice) => choice['step_number']).toList(), <int>[
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      // Air-fry: the crisp step is canonical, so no variant row anywhere.
      expect(choices.every((choice) => choice['is_variant'] == 0), isTrue);
      final crisp = choices.firstWhere((choice) => choice['step_number'] == 5);
      expect(crisp['equipment_id'], 3, reason: 'air fryer');
      expect(crisp['variant_id'], isNull);
    });

    test('a pan-fry start pins the variant row on the crisp step', () async {
      final session = await startBelly('pan_fry');

      final choices = await harness.db.query(
        'session_step_choices',
        where: 'session_id = ? AND step_number = ?',
        whereArgs: <Object?>[int.parse(session.id), 5],
      );
      final crisp = choices.single;
      expect(crisp['is_variant'], 1);
      expect(crisp['variant_id'], 1, reason: 'the only seeded variant');
      expect(crisp['equipment_id'], 1, reason: 'stovetop');
    });

    test('a guide-anyway start freezes the missing codes in the row', () async {
      final result = await engine.start(
        recipeSlug: 'chicken-adobo',
        methodKey: null,
        guideAnyway: true,
        nowUtc: now,
      );
      final session = result.session!;
      expect(session.startedWithoutAvailability, isTrue);

      final row = (await harness.db.query('cooking_sessions')).single;
      expect(row['started_without_availability'], 1);
      expect(row['missing_requirements_json'], '["ingredient:bay_leaf"]');
    });

    test('a second start is refused while one is active', () async {
      await startBelly('air_fry');
      final second = await engine.start(
        recipeSlug: 'chicken-adobo',
        methodKey: null,
        guideAnyway: true,
        nowUtc: now,
      );
      expect(second.session, isNull);
      expect(second.activeSession, isNotNull);
      expect(await harness.db.query('cooking_sessions'), hasLength(1));
    });
  });

  group('resume after relaunch', () {
    test(
      'the method, pinned path, step and timer survive a cold start',
      () async {
        final session = await startBelly('pan_fry');
        // Walk to the pan-fry crisp step (step 5) and start its 720 s timer.
        for (var step = 1; step < 5; step++) {
          await engine.advance(sessionId: session.id, nowUtc: now);
        }
        final started = await engine.startTimer(
          sessionId: session.id,
          nowUtc: now,
        );
        expect(started.remaining, const Duration(seconds: 720));

        // Force-kill: close the file and open a brand-new store + engine.
        final relaunched = await reopen(harness, seed: true);
        harness = relaunched;
        final resumedEngine = LocalGuidedCookingEngine(
          store: harness.guideStore,
        );

        final active = await harness.sessions.loadActiveSession();
        expect(active, isNotNull);
        expect(active!.id, session.id);
        expect(active.currentStepNumber, 5);
        expect(active.status, SessionStatus.inProgress);
        expect(active.path.methodKey, 'pan_fry');
        expect(active.timerDurationSeconds, 720);
        expect(active.timerStartedAtUtc, now);

        final pinned = active.path.step(5)!;
        expect(pinned.isVariant, isTrue);
        expect(pinned.variantMethodKey, 'pan_fry');
        expect(pinned.equipmentCode, 'stovetop');
        expect(pinned.snapshot.durationSeconds, 720);
        expect(pinned.snapshot.spriteKey, 'step_cook_stovetop');
        expect(pinned.snapshot.instruction, contains('pan'));

        final step = await resumedEngine.currentStep(
          sessionId: session.id,
          nowUtc: now.add(const Duration(minutes: 10)),
        );
        expect(step.stepNumber, 5);
        expect(step.spriteKey, 'step_cook_stovetop');
        expect(
          formatCountdown(step.timer.remaining),
          '02:00',
          reason: '720 s started 10 min ago leaves 2 min',
        );
        expect(step.timer.phase, TimerPhase.running);
      },
    );

    test('advancing clears the persisted timer columns', () async {
      final session = await startBelly('air_fry');
      // Step 1 is prep; step 2 is the timed blanch (420 s).
      await engine.advance(sessionId: session.id, nowUtc: now);
      await engine.startTimer(sessionId: session.id, nowUtc: now);
      await engine.advance(sessionId: session.id, nowUtc: now);

      final row = (await harness.db.query('cooking_sessions')).single;
      expect(row['timer_started_at'], isNull);
      expect(row['timer_duration_seconds'], isNull);
      expect(row['current_step_number'], 3);
    });

    test('abandon records the status and clears the timer', () async {
      final session = await startBelly('air_fry');
      await engine.advance(sessionId: session.id, nowUtc: now);
      await engine.startTimer(sessionId: session.id, nowUtc: now);
      final abandoned = await engine.abandon(
        sessionId: session.id,
        confirmed: true,
        nowUtc: now.add(const Duration(minutes: 2)),
      );

      expect(abandoned.status, SessionStatus.abandoned);
      final row = (await harness.db.query('cooking_sessions')).single;
      expect(row['status'], 'abandoned');
      expect(row['timer_started_at'], isNull);
      expect(row['completed_at'], isNull);
      expect(
        await harness.db.query('session_step_choices'),
        hasLength(6),
        reason: 'the pinned path is kept for history',
      );
      expect(await harness.sessions.loadActiveSession(), isNull);
    });
  });

  group('completion transaction', () {
    test(
      'completion writes the usage events and completes atomically',
      () async {
        final session = await startBelly('air_fry');
        for (var step = 0; step < 6; step++) {
          await engine.advance(
            sessionId: session.id,
            nowUtc: now.add(Duration(minutes: step)),
          );
        }
        final lines = await engine.review(sessionId: session.id);
        final result = await engine.complete(
          sessionId: session.id,
          lines: lines,
          nowUtc: now.add(const Duration(minutes: 30)),
        );

        expect(result.outcome, CompletionOutcome.completed);
        expect(
          result.eventsWritten,
          result.usedItCount + result.restockCorrections,
        );

        final sessionRow = (await harness.db.query('cooking_sessions')).single;
        expect(sessionRow['status'], 'completed');
        expect(sessionRow['completed_at'], isNotNull);
        expect(sessionRow['timer_started_at'], isNull);

        final events = await harness.db.query('stock_event');
        expect(events, hasLength(result.eventsWritten));
        expect(
          events.every(
            (event) => event['cooking_session_id'] == int.parse(session.id),
          ),
          isTrue,
        );
        // pork_belly + salt were "have" and default to Used it -> low.
        expect(
          await harness.repositories.stock.getStatus('pork_belly'),
          StockStatus.low,
        );
      },
    );

    test('a repeated completion is idempotent', () async {
      final session = await startBelly('air_fry');
      for (var step = 0; step < 6; step++) {
        await engine.advance(sessionId: session.id, nowUtc: now);
      }
      final lines = await engine.review(sessionId: session.id);
      final first = await engine.complete(
        sessionId: session.id,
        lines: lines,
        nowUtc: now,
      );
      expect(first.outcome, CompletionOutcome.completed);
      final eventsAfterFirst = await harness.db.query('stock_event');

      final second = await engine.complete(
        sessionId: session.id,
        lines: lines,
        nowUtc: now.add(const Duration(minutes: 1)),
      );
      expect(second.outcome, CompletionOutcome.alreadyCompleted);
      expect(second.eventsWritten, 0);
      expect(
        await harness.db.query('stock_event'),
        hasLength(eventsAfterFirst.length),
      );
    });

    test('an invalid line writes nothing', () async {
      final session = await startBelly('air_fry');
      for (var step = 0; step < 6; step++) {
        await engine.advance(sessionId: session.id, nowUtc: now);
      }
      // bay_leaf is optional in this dish and "out": Used it is not allowed
      // for an out line, and the store rejects it before any write.
      final lines = await engine.review(sessionId: session.id);
      final bayLeaf = lines.firstWhere(
        (line) => line.ingredientCode == 'bay_leaf',
      );
      final invalid = <CompletionLine>[
        for (final line in lines)
          line.ingredientCode == 'bay_leaf'
              ? line.copyWith(choice: CompletionChoice.usedIt)
              : line,
      ];
      expect(bayLeaf.allowedChoices.contains(CompletionChoice.usedIt), isFalse);

      final result = await engine.complete(
        sessionId: session.id,
        lines: invalid,
        nowUtc: now,
      );
      expect(result.outcome, CompletionOutcome.rejected);
      expect(result.error, EngineError.invalidCompletionLine);
      expect(await harness.db.query('stock_event'), isEmpty);
      expect(
        (await harness.db.query('cooking_sessions')).single['status'],
        'in_progress',
      );
    });

    test('a failure after the first event rolls the completion back', () async {
      final session = await startBelly('air_fry');
      for (var step = 0; step < 6; step++) {
        await engine.advance(sessionId: session.id, nowUtc: now);
      }
      final lines = await engine.review(sessionId: session.id);

      // Inject a failure on the second event insert, after the first write.
      await harness.db.execute(
        'CREATE TRIGGER fail_second_event BEFORE INSERT ON stock_event '
        'WHEN (SELECT COUNT(*) FROM stock_event) >= 1 '
        "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );

      final result = await engine.complete(
        sessionId: session.id,
        lines: lines,
        nowUtc: now,
      );

      expect(result.outcome, CompletionOutcome.rejected);
      expect(result.eventsWritten, 0);
      expect(await harness.db.query('stock_event'), isEmpty);
      expect(
        (await harness.db.query('cooking_sessions')).single['status'],
        'in_progress',
        reason: 'the conditional completion never committed',
      );
      expect(
        await harness.repositories.stock.getStatus('pork_belly'),
        StockStatus.have,
        reason: 'the first status update rolled back too',
      );
    });

    test(
      'reset is blocked while a cook is in progress, allowed after',
      () async {
        final session = await startBelly('air_fry');
        await expectLater(
          harness.repositories.resetDemoData(),
          throwsA(isA<StateError>()),
        );

        await engine.abandon(
          sessionId: session.id,
          confirmed: true,
          nowUtc: now,
        );
        await harness.repositories.resetDemoData();
        expect(await harness.db.query('cooking_sessions'), isEmpty);
        expect(await harness.db.query('stock_event'), isEmpty);
      },
    );
  });
}
