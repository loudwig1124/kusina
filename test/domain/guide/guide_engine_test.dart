import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/guide/guide_engine.dart';
import 'package:kusina/domain/guide/guide_models.dart';
import 'package:kusina/domain/guide/guide_rules.dart';
import 'package:kusina/domain/models/stock.dart';

import 'guide_harness.dart';

void main() {
  late EngineHarness harness;

  setUp(() async {
    harness = await createEngineHarness();
  });

  Future<GuidedSession> startAdobo({
    EngineHarness? on,
    bool guideAnyway = true,
  }) {
    return (on ?? harness).engine
        .start(
          recipeSlug: 'chicken-adobo',
          methodKey: null,
          guideAnyway: guideAnyway,
          nowUtc: testNow,
        )
        .then((result) {
          expect(result.error, isNull, reason: 'start must succeed');
          return result.session!;
        });
  }

  Future<GuidedSession> startBelly(
    EngineHarness on, {
    required String method,
    bool guideAnyway = false,
  }) async {
    final result = await on.engine.start(
      recipeSlug: 'crispy-pork-belly',
      methodKey: method,
      guideAnyway: guideAnyway,
      nowUtc: testNow,
    );
    expect(result.error, isNull);
    return result.session!;
  }

  group('start (docs/09 §5.3, T-05..T-14)', () {
    test('T-11 a ready dish starts at step 1 with no stock writes', () async {
      final ready = await createEngineHarness();
      // Restock the bay leaf so Adobo is ready.
      await ready.fixtures.repositories.stock.setStatus(
        ingredientCode: 'bay_leaf',
        to: StockStatus.have,
        reason: StockReason.restock,
      );
      final eventsBefore = (await ready.allEvents()).length;

      final session = await startAdobo(on: ready);

      expect(session.status, SessionStatus.inProgress);
      expect(session.currentStepNumber, 1);
      expect(session.totalSteps, 7);
      expect(session.startedWithoutAvailability, isFalse);
      expect(session.missingCodes, isEmpty);
      expect(session.path.methodKey, isNull);
      expect(session.path.stepCount, 7);
      expect(
        session.path.steps.values.every((step) => step.isVariant),
        isFalse,
      );
      expect((await ready.allEvents()).length, eventsBefore);
      expect(await ready.statusOf('bay_leaf'), StockStatus.have);
    });

    test('T-12 a blocked dish does not start without guide-anyway', () async {
      final result = await harness.engine.start(
        recipeSlug: 'chicken-adobo',
        methodKey: null,
        guideAnyway: false,
        nowUtc: testNow,
      );

      expect(result.session, isNull);
      expect(result.blockedBy, isNotNull);
      expect(result.blockedBy!.missingCodes, <String>['ingredient:bay_leaf']);
      expect(await harness.store.sessions(), isEmpty);
    });

    test(
      'T-13 guide-anyway freezes the missing codes on the session',
      () async {
        final session = await startAdobo();

        expect(session.startedWithoutAvailability, isTrue);
        expect(session.missingCodes, <String>['ingredient:bay_leaf']);
        expect(await harness.allEvents(), isEmpty);

        // T-53: equipment edits after start never rewrite the frozen list.
        await harness.fixtures.repositories.equipment.setOwned(<String>{
          'stovetop',
          'air_fryer',
          'oven',
        });
        final step = await harness.engine.currentStep(
          sessionId: session.id,
          nowUtc: testNow,
        );
        expect(step.stepNumber, 1);
        expect(
          (await harness.engine.session(session.id))!.missingCodes,
          <String>['ingredient:bay_leaf'],
        );
      },
    );

    test('T-14 a second start returns the active session', () async {
      final first = await startAdobo();
      final second = await harness.engine.start(
        recipeSlug: 'sinangag',
        methodKey: null,
        guideAnyway: true,
        nowUtc: testNow,
      );

      expect(second.session, isNull);
      expect(second.activeSession!.id, first.id);
      expect(await harness.store.sessions(), hasLength(1));
    });

    test('T-09 a method dish with no pick writes nothing', () async {
      final result = await harness.engine.start(
        recipeSlug: 'crispy-pork-belly',
        methodKey: null,
        guideAnyway: true,
        nowUtc: testNow,
      );

      expect(result.error, EngineError.methodChoiceRequired);
      expect(await harness.store.sessions(), isEmpty);
    });

    test('four start combinations: owned x pan-fry/air-fry', () async {
      // Owned both: both picks start ready.
      for (final method in <String>['pan_fry', 'air_fry']) {
        final both = await createEngineHarness(
          ownedEquipment: <String>{'stovetop', 'air_fryer'},
        );
        final result = await both.engine.start(
          recipeSlug: 'crispy-pork-belly',
          methodKey: method,
          guideAnyway: false,
          nowUtc: testNow,
        );
        expect(result.session, isNotNull, reason: 'both owned, $method');
        expect(result.session!.startedWithoutAvailability, isFalse);
      }

      // Stovetop only: Pan-fry starts, Air-fry is blocked on the air fryer.
      final stovetopOnly = await createEngineHarness(
        ownedEquipment: <String>{'stovetop'},
      );
      final panFry = await stovetopOnly.engine.start(
        recipeSlug: 'crispy-pork-belly',
        methodKey: 'pan_fry',
        guideAnyway: false,
        nowUtc: testNow,
      );
      expect(panFry.session, isNotNull);
      expect(
        panFry.session!.path.step(5)!.variantMethodKey,
        'pan_fry',
        reason: 'the pan-fry variant is pinned',
      );

      final stovetopOnlyBlocked = await createEngineHarness(
        ownedEquipment: <String>{'stovetop'},
      );
      final airFryBlocked = await stovetopOnlyBlocked.engine.start(
        recipeSlug: 'crispy-pork-belly',
        methodKey: 'air_fry',
        guideAnyway: false,
        nowUtc: testNow,
      );
      expect(airFryBlocked.session, isNull);
      expect(airFryBlocked.blockedBy!.missingCodes, <String>[
        'equipment:air_fryer',
      ]);

      // Air fryer only: both picks need the shared stovetop, so both block.
      final airFryerOnly = await createEngineHarness(
        ownedEquipment: <String>{'air_fryer'},
      );
      for (final method in <String>['pan_fry', 'air_fry']) {
        final result = await airFryerOnly.engine.start(
          recipeSlug: 'crispy-pork-belly',
          methodKey: method,
          guideAnyway: false,
          nowUtc: testNow,
        );
        expect(result.session, isNull, reason: 'air-fryer only, $method');
        expect(result.blockedBy!.missingCodes, <String>['equipment:stovetop']);
      }
    });

    test(
      'a guide-anyway start pins the blocked method, never the other',
      () async {
        final stovetopOnly = await createEngineHarness(
          ownedEquipment: <String>{'stovetop'},
        );
        final result = await stovetopOnly.engine.start(
          recipeSlug: 'crispy-pork-belly',
          methodKey: 'air_fry',
          guideAnyway: true,
          nowUtc: testNow,
        );

        final session = result.session!;
        expect(session.path.methodKey, 'air_fry');
        expect(session.startedWithoutAvailability, isTrue);
        expect(session.missingCodes, <String>['equipment:air_fryer']);
        final crisp = session.path.step(5)!;
        expect(crisp.equipmentCode, 'air_fryer');
        expect(crisp.isVariant, isFalse);
        expect(crisp.snapshot.durationSeconds, 1200);
      },
    );
  });

  group('method pinning (docs/09 §4.2/§4.6)', () {
    test('T-05 Air-fry pins the canonical air-fryer step', () async {
      final both = await createEngineHarness(
        ownedEquipment: <String>{'stovetop', 'air_fryer'},
      );
      final session = await startBelly(both, method: 'air_fry');

      final view = await both.engine.currentStep(
        sessionId: session.id,
        nowUtc: testNow,
      );
      expect(view.stepNumber, 1);
      final crisp = session.path.step(5)!;
      expect(crisp.isVariant, isFalse);
      expect(crisp.equipmentCode, 'air_fryer');
      expect(crisp.snapshot.durationSeconds, 1200);
      expect(crisp.snapshot.spriteKey, 'step_cook_air_fryer');
      expect(crisp.snapshot.variantMethodKey, isNull);

      // Walk to the crisp step and check what the guide renders.
      for (var step = 1; step < 5; step++) {
        await both.engine.advance(sessionId: session.id, nowUtc: testNow);
      }
      final crispView = await both.engine.currentStep(
        sessionId: session.id,
        nowUtc: testNow,
      );
      expect(crispView.stepNumber, 5);
      expect(crispView.spriteKey, 'step_cook_air_fryer');
      expect(crispView.instruction.toLowerCase(), contains('air-fry'));
      expect(crispView.equipmentCode, 'air_fryer');
    });

    test('T-06 Pan-fry pins the stovetop variant', () async {
      final stovetopOnly = await createEngineHarness(
        ownedEquipment: <String>{'stovetop'},
      );
      final session = await startBelly(stovetopOnly, method: 'pan_fry');

      final crisp = session.path.step(5)!;
      expect(crisp.isVariant, isTrue);
      expect(crisp.variantMethodKey, 'pan_fry');
      expect(crisp.equipmentCode, 'stovetop');
      expect(crisp.snapshot.durationSeconds, 720);
      expect(crisp.snapshot.spriteKey, 'step_cook_stovetop');
      expect(crisp.snapshot.instruction, contains('pan'));

      // The air fryer never appears in the pinned path.
      expect(
        session.path.steps.values
            .map((step) => step.equipmentCode)
            .where((code) => code == 'air_fryer'),
        isEmpty,
      );
    });

    test('changing the recipe content after start does not alter the session', () async {
      final stovetopOnly = await createEngineHarness(
        ownedEquipment: <String>{'stovetop'},
      );
      final session = await startBelly(stovetopOnly, method: 'pan_fry');
      final originalCrisp = session.path.step(5)!.snapshot.instruction;
      for (var step = 1; step < 5; step++) {
        await stovetopOnly.engine.advance(
          sessionId: session.id,
          nowUtc: testNow,
        );
      }

      // The seed is edited mid-cook: the pan-fry variant copy changes.
      final original = (await stovetopOnly.recipe('crispy-pork-belly'))!;
      stovetopOnly.recipeOverrides['crispy-pork-belly'] =
          withVariantInstruction(
            original,
            5,
            'pan_fry',
            'EDITED: fry the belly in a very hot pan.',
          );

      // A fresh engine over the edited content still serves the pinned session.
      final relaunched = LocalGuidedCookingEngine(store: stovetopOnly.store);
      final resumed = await relaunched.currentStep(
        sessionId: session.id,
        nowUtc: testNow,
      );
      expect(resumed.instruction, originalCrisp);
      expect(resumed.instruction, isNot(contains('EDITED')));
      expect(resumed.spriteKey, 'step_cook_stovetop');

      // The edit is live: a new cook after abandoning sees the new copy.
      await stovetopOnly.engine.abandon(
        sessionId: session.id,
        confirmed: true,
        nowUtc: testNow,
      );
      final fresh = await stovetopOnly.engine.start(
        recipeSlug: 'crispy-pork-belly',
        methodKey: 'pan_fry',
        guideAnyway: true,
        nowUtc: testNow,
      );
      expect(
        fresh.session!.path.step(5)!.snapshot.instruction,
        contains('EDITED'),
      );
    });

    test('a single-path dish rejects a method key', () async {
      final result = await harness.engine.start(
        recipeSlug: 'chicken-adobo',
        methodKey: 'pan_fry',
        guideAnyway: true,
        nowUtc: testNow,
      );
      expect(result.error, EngineError.methodChoiceRequired);
    });
  });

  group('advance and abandon (docs/09 §5.2)', () {
    test('tap-to-advance walks 1..N and then the review sentinel', () async {
      final session = await startAdobo();
      for (var step = 2; step <= 7; step++) {
        final view = await harness.engine.advance(
          sessionId: session.id,
          nowUtc: testNow,
        );
        expect(view.stepNumber, step);
        expect(view.isReview, isFalse);
        expect(view.progressFraction, closeTo((step - 1) / 7, 1e-9));
      }
      final review = await harness.engine.advance(
        sessionId: session.id,
        nowUtc: testNow,
      );
      expect(review.isReview, isTrue);
      expect(review.progressPercent, 100);
      final stored = await harness.engine.session(session.id);
      expect(stored!.status, SessionStatus.inProgress);
      expect(stored.isReview, isTrue);
    });

    test(
      'T-16 advancing from the last step does not complete the session',
      () async {
        final session = await startAdobo();
        for (var index = 0; index < 7; index++) {
          await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
        }
        final stored = await harness.engine.session(session.id);
        expect(stored!.currentStepNumber, 8);
        expect(stored.status, SessionStatus.inProgress);
        expect(await harness.allEvents(), isEmpty);
      },
    );

    test('T-17 bumping the sentinel is AlreadyAtReview', () async {
      final session = await startAdobo();
      for (var index = 0; index < 7; index++) {
        await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      }
      await expectLater(
        harness.engine.advance(sessionId: session.id, nowUtc: testNow),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.alreadyAtReview,
          ),
        ),
      );
    });

    test('currentStep at the sentinel asks for the review', () async {
      final session = await startAdobo();
      for (var index = 0; index < 7; index++) {
        await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      }
      await expectLater(
        harness.engine.currentStep(sessionId: session.id, nowUtc: testNow),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.alreadyAtReview,
          ),
        ),
      );
    });

    test('T-18 abandon needs confirmation', () async {
      final session = await startAdobo();
      await expectLater(
        harness.engine.abandon(
          sessionId: session.id,
          confirmed: false,
          nowUtc: testNow,
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.abandonNotConfirmed,
          ),
        ),
      );
      expect(
        (await harness.engine.session(session.id))!.status,
        SessionStatus.inProgress,
      );
    });

    test(
      'T-19 abandoning clears the timer and writes no stock events',
      () async {
        final session = await startAdobo();
        await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
        await harness.engine.startTimer(sessionId: session.id, nowUtc: testNow);

        final abandoned = await harness.engine.abandon(
          sessionId: session.id,
          confirmed: true,
          nowUtc: testNow.add(const Duration(minutes: 5)),
        );

        expect(abandoned.status, SessionStatus.abandoned);
        expect(abandoned.timerStartedAtUtc, isNull);
        expect(abandoned.timerDurationSeconds, isNull);
        expect(await harness.allEvents(), isEmpty);
        await expectLater(harness.engine.activeSession(), completion(isNull));
      },
    );

    test('T-20 a terminal session rejects advance and abandon', () async {
      final session = await startAdobo();
      await harness.engine.abandon(
        sessionId: session.id,
        confirmed: true,
        nowUtc: testNow,
      );

      await expectLater(
        harness.engine.advance(sessionId: session.id, nowUtc: testNow),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.sessionNotActive,
          ),
        ),
      );
      await expectLater(
        harness.engine.abandon(
          sessionId: session.id,
          confirmed: true,
          nowUtc: testNow,
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.sessionNotActive,
          ),
        ),
      );
    });
  });

  group('timer (docs/09 §6)', () {
    test('T-21 a running timer derives its remaining time', () async {
      final session = await startAdobo();
      await harness.engine.advance(sessionId: session.id, nowUtc: testNow);

      final started = await harness.engine.startTimer(
        sessionId: session.id,
        nowUtc: testNow,
      );
      expect(started.phase, TimerPhase.running);
      expect(started.remaining, const Duration(seconds: 480));

      final later = await harness.engine.timerState(
        sessionId: session.id,
        nowUtc: testNow.add(const Duration(minutes: 3)),
      );
      expect(later.remaining, const Duration(seconds: 300));
      expect(timerCopy(later), '05:00 left');
    });

    test('T-26 the timer cannot be started twice', () async {
      final session = await startAdobo();
      await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      await harness.engine.startTimer(sessionId: session.id, nowUtc: testNow);

      await expectLater(
        harness.engine.startTimer(sessionId: session.id, nowUtc: testNow),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.timerAlreadyRunning,
          ),
        ),
      );
    });

    test('T-27 a step without a timer cannot start one', () async {
      final session = await startAdobo();
      await expectLater(
        harness.engine.startTimer(sessionId: session.id, nowUtc: testNow),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.timerNotAvailable,
          ),
        ),
      );
    });

    test('T-15 advancing clears the timer', () async {
      final session = await startAdobo();
      await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      await harness.engine.startTimer(sessionId: session.id, nowUtc: testNow);

      await harness.engine.advance(
        sessionId: session.id,
        nowUtc: testNow.add(const Duration(seconds: 30)),
      );
      final stored = await harness.engine.session(session.id);
      expect(stored!.timerStartedAtUtc, isNull);
      expect(stored.timerDurationSeconds, isNull);
      final timer = await harness.engine.timerState(
        sessionId: session.id,
        nowUtc: testNow.add(const Duration(minutes: 10)),
      );
      expect(timer.phase, TimerPhase.idle);
    });

    test(
      'T-28 a cold start 10 min later derives overrun, step unchanged',
      () async {
        final session = await startAdobo();
        await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
        await harness.engine.startTimer(
          sessionId: session.id,
          nowUtc: testNow.add(const Duration(minutes: 4)),
        );
        expect(
          (await harness.engine.session(session.id))!.currentStepNumber,
          2,
        );

        // Relaunch: a brand-new engine over the same persisted session, ten
        // minutes after the timer was started.
        final relaunched = LocalGuidedCookingEngine(store: harness.store);
        final at = testNow.add(const Duration(minutes: 14));
        final info = await relaunched.onResume(
          sessionId: session.id,
          nowUtc: at,
        );

        expect(info.step!.stepNumber, 2, reason: 'no auto-advance on relaunch');
        expect(info.timer.phase, TimerPhase.overrun);
        expect(info.session.currentStepNumber, 2);
        expect(info.timerFinishedAgo, const Duration(minutes: 2));
        expect(info.resumeCopy, contains('The timer finished 2 min ago.'));
        expect(info.resumeCopy, contains('You were away 10 min.'));
      },
    );

    test('T-22 a deadline crossed on screen is done, not overrun', () async {
      final session = await startAdobo();
      await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      final timerStart = testNow;
      await harness.engine.startTimer(
        sessionId: session.id,
        nowUtc: timerStart,
      );
      final deadline = timerStart.add(const Duration(seconds: 480));

      final atDeadline = await harness.engine.timerState(
        sessionId: session.id,
        nowUtc: deadline,
      );
      expect(atDeadline.phase, TimerPhase.done);
      expect(atDeadline.overdue, Duration.zero);
    });

    test('a 25:00 timer survives a cold start with the same remaining time', () async {
      final session = await startAdobo();
      // Adobo step 5 is the 1500 s simmer (25:00).
      for (var index = 0; index < 4; index++) {
        await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      }
      final timerStart = testNow;
      final started = await harness.engine.startTimer(
        sessionId: session.id,
        nowUtc: timerStart,
      );
      expect(formatCountdown(started.remaining), '25:00');

      // Force-kill and relaunch ten minutes later: a brand-new engine derives
      // the remaining time from the absolute start, and the step is unchanged.
      final relaunched = LocalGuidedCookingEngine(store: harness.store);
      final at = timerStart.add(const Duration(minutes: 10));
      final derived = await relaunched.timerState(
        sessionId: session.id,
        nowUtc: at,
      );
      expect(derived.phase, TimerPhase.running);
      expect(formatCountdown(derived.remaining), '15:00');

      final info = await relaunched.onResume(sessionId: session.id, nowUtc: at);
      expect(info.step!.stepNumber, 5, reason: 'never auto-advances');
      expect(info.session.currentStepNumber, 5);
      expect(info.resumeCopy, 'Welcome back. Step 5 of 7.');
    });

    test('T-29 a 30 h old session is stale but still in progress', () async {
      final old = DateTime.utc(2026, 1, 1, 9);
      final session = await harness.engine.start(
        recipeSlug: 'chicken-adobo',
        methodKey: null,
        guideAnyway: true,
        nowUtc: old,
      );
      await harness.engine.advance(sessionId: session.session!.id, nowUtc: old);
      await harness.engine.startTimer(
        sessionId: session.session!.id,
        nowUtc: old,
      );

      final info = await harness.engine.onResume(
        sessionId: session.session!.id,
        nowUtc: old.add(const Duration(hours: 30)),
      );
      expect(info.stale, isTrue);
      expect(info.session.status, SessionStatus.inProgress);
      expect(info.timer.phase, TimerPhase.overrun);
    });

    test('the timer never changes the step', () async {
      final session = await startAdobo();
      await harness.engine.advance(sessionId: session.id, nowUtc: testNow);
      await harness.engine.startTimer(sessionId: session.id, nowUtc: testNow);

      for (final offset in <int>[60, 480, 481, 3600]) {
        final at = testNow.add(Duration(seconds: offset));
        await harness.engine.timerState(sessionId: session.id, nowUtc: at);
        final stored = await harness.engine.session(session.id);
        expect(stored!.currentStepNumber, 2, reason: 'offset $offset');
        expect(stored.status, SessionStatus.inProgress);
      }
    });
  });

  group('usage review and completion (docs/09 §8)', () {
    Future<String> reachReview([EngineHarness? on]) async {
      final target = on ?? harness;
      final session = await startAdobo(on: target);
      for (var index = 0; index < 7; index++) {
        await target.engine.advance(sessionId: session.id, nowUtc: testNow);
      }
      return session.id;
    }

    test('T-44 review defaults follow the status table', () async {
      final sessionId = await reachReview();
      final lines = await harness.engine.review(sessionId: sessionId);

      final byCode = <String, CompletionLine>{
        for (final line in lines) line.ingredientCode: line,
      };
      expect(byCode['chicken_thighs']!.choice, CompletionChoice.usedIt);
      expect(byCode['soy_sauce']!.choice, CompletionChoice.usedIt);
      expect(byCode['garlic']!.choice, CompletionChoice.usedIt);
      expect(byCode['bay_leaf']!.choice, CompletionChoice.didntUse);
      expect(byCode['bay_leaf']!.isRequired, isTrue);
      expect(byCode['cooking_oil']!.isRequired, isFalse);
      expect(byCode['cooking_oil']!.choice, CompletionChoice.didntUse);
      expect(byCode['bay_leaf']!.allowedChoices, <CompletionChoice>[
        CompletionChoice.didntUse,
        CompletionChoice.usedItUp,
      ]);
    });

    test(
      'T-34 default completion writes used_some for required have lines',
      () async {
        final sessionId = await reachReview();
        final lines = await harness.engine.review(sessionId: sessionId);

        final result = await harness.engine.complete(
          sessionId: sessionId,
          lines: lines,
          nowUtc: testNow.add(const Duration(minutes: 1)),
        );

        expect(result.outcome, CompletionOutcome.completed);
        expect(result.usedItCount, 4);
        expect(result.eventsWritten, 4);
        final session = await harness.engine.session(sessionId);
        expect(session!.status, SessionStatus.completed);
        expect(session.completedAtUtc, isNotNull);
        expect(session.timerStartedAtUtc, isNull);

        expect(await harness.statusOf('chicken_thighs'), StockStatus.low);
        expect(await harness.statusOf('soy_sauce'), StockStatus.low);
        expect(await harness.statusOf('vinegar'), StockStatus.low);
        expect(await harness.statusOf('garlic'), StockStatus.low);
        expect(await harness.statusOf('bay_leaf'), StockStatus.out);
        expect(await harness.statusOf('sugar'), StockStatus.have);
        final events = await harness.allEvents();
        expect(events, hasLength(4));
        expect(
          events.every((event) => event.reason == StockReason.usedSome),
          isTrue,
        );
        expect(
          events.every((event) => event.cookingSessionId == sessionId),
          isTrue,
        );
      },
    );

    test(
      'T-35/T-42/T-43 no-op choices write nothing but still complete',
      () async {
        final sessionId = await reachReview();
        final lines = await harness.engine.review(sessionId: sessionId);
        final patched = <CompletionLine>[
          for (final line in lines)
            line.ingredientCode == 'chicken_thighs'
                ? line.copyWith(choice: CompletionChoice.didntUse)
                : line.ingredientCode == 'bay_leaf'
                ? line.copyWith(choice: CompletionChoice.usedItUp)
                : line.copyWith(choice: CompletionChoice.didntUse),
        ];

        final result = await harness.engine.complete(
          sessionId: sessionId,
          lines: patched,
          nowUtc: testNow,
        );

        expect(result.outcome, CompletionOutcome.completed);
        expect(result.eventsWritten, 0);
        expect(await harness.allEvents(), isEmpty);
        expect(await harness.statusOf('chicken_thighs'), StockStatus.have);
        expect(await harness.statusOf('bay_leaf'), StockStatus.out);
        expect(
          (await harness.engine.session(sessionId))!.status,
          SessionStatus.completed,
        );
      },
    );

    test('T-35 Used it on a low line is a no-op', () async {
      final lowStatuses = <String, StockStatus>{
        ...harness.fixtures.statuses,
        'chicken_thighs': StockStatus.low,
      };
      final lowHarness = await createEngineHarness(statuses: lowStatuses);
      final sessionId = await reachReview(lowHarness);
      final lines = await lowHarness.engine.review(sessionId: sessionId);
      final chicken = lines.firstWhere(
        (line) => line.ingredientCode == 'chicken_thighs',
      );
      expect(chicken.choice, CompletionChoice.usedIt);
      expect(chicken.isNoOp, isTrue);

      final result = await lowHarness.engine.complete(
        sessionId: sessionId,
        lines: lines,
        nowUtc: testNow,
      );

      expect(result.outcome, CompletionOutcome.completed);
      expect(await lowHarness.statusOf('chicken_thighs'), StockStatus.low);
      final chickenEvents = await lowHarness.eventsFor('chicken_thighs');
      expect(chickenEvents, isEmpty);
      // The other required have lines still wrote their usage.
      expect(result.eventsWritten, 3);
    });

    test('T-41 Used it on out is rejected with zero writes', () async {
      final sessionId = await reachReview();
      final lines = await harness.engine.review(sessionId: sessionId);
      final invalid = <CompletionLine>[
        for (final line in lines)
          line.ingredientCode == 'bay_leaf'
              ? line.copyWith(choice: CompletionChoice.usedIt)
              : line,
      ];

      final result = await harness.engine.complete(
        sessionId: sessionId,
        lines: invalid,
        nowUtc: testNow,
      );

      expect(result.outcome, CompletionOutcome.rejected);
      expect(result.error, EngineError.invalidCompletionLine);
      expect(result.eventsWritten, 0);
      expect(await harness.allEvents(), isEmpty);
      expect(await harness.statusOf('bay_leaf'), StockStatus.out);
      expect(
        (await harness.engine.session(sessionId))!.status,
        SessionStatus.inProgress,
      );
    });

    test(
      'T-45 unknown + I have it + Used it chains restock then used_some',
      () async {
        final unknownStatuses = <String, StockStatus>{
          ...harness.fixtures.statuses,
          'garlic': StockStatus.unknown,
        };
        final unknownHarness = await createEngineHarness(
          statuses: unknownStatuses,
        );
        final sessionId = await reachReview(unknownHarness);
        final lines = await unknownHarness.engine.review(sessionId: sessionId);
        final patched = <CompletionLine>[
          for (final line in lines)
            line.ingredientCode == 'garlic'
                ? line.copyWith(
                    restockToHave: true,
                    choice: CompletionChoice.usedIt,
                  )
                : line,
        ];

        final result = await unknownHarness.engine.complete(
          sessionId: sessionId,
          lines: patched,
          nowUtc: testNow,
        );

        expect(result.outcome, CompletionOutcome.completed);
        expect(result.restockCorrections, 1);
        expect(await unknownHarness.statusOf('garlic'), StockStatus.low);
        final events = await unknownHarness.eventsFor('garlic');
        expect(events, hasLength(2));
        expect(events.last.reason, StockReason.usedSome);
        expect(events.last.from, StockStatus.have);
        expect(events.last.to, StockStatus.low);
        expect(events.last.cookingSessionId, sessionId);
        expect(events.first.reason, StockReason.restock);
        expect(events.first.from, StockStatus.unknown);
      },
    );

    test('a second completion is idempotent', () async {
      final sessionId = await reachReview();
      final lines = await harness.engine.review(sessionId: sessionId);
      final first = await harness.engine.complete(
        sessionId: sessionId,
        lines: lines,
        nowUtc: testNow,
      );
      expect(first.outcome, CompletionOutcome.completed);
      final eventsAfterFirst = (await harness.allEvents()).length;
      final statusesAfterFirst = await harness.statusesOf(
        lines.map((line) => line.ingredientCode).toList(),
      );

      final second = await harness.engine.complete(
        sessionId: sessionId,
        lines: lines,
        nowUtc: testNow.add(const Duration(minutes: 1)),
      );

      expect(second.outcome, CompletionOutcome.alreadyCompleted);
      expect(second.eventsWritten, 0);
      expect((await harness.allEvents()).length, eventsAfterFirst);
      expect(
        await harness.statusesOf(
          lines.map((line) => line.ingredientCode).toList(),
        ),
        statusesAfterFirst,
      );
    });

    test('complete before the review is rejected', () async {
      final session = await startAdobo();
      await expectLater(
        harness.engine.review(sessionId: session.id),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.completionIncomplete,
          ),
        ),
      );
      await expectLater(
        harness.engine.complete(
          sessionId: session.id,
          lines: const <CompletionLine>[],
          nowUtc: testNow,
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.completionIncomplete,
          ),
        ),
      );
    });

    test('a line for an ingredient outside the recipe is rejected', () async {
      final sessionId = await reachReview();
      final lines = await harness.engine.review(sessionId: sessionId);
      final bogus = <CompletionLine>[
        ...lines,
        CompletionLine(
          ingredientCode: 'pork_belly',
          ingredientName: 'Pork belly',
          isRequired: true,
          status: StockStatus.have,
          choice: CompletionChoice.usedIt,
          allowedChoices: allowedChoicesFor(StockStatus.have),
          restockToHave: false,
        ),
      ];

      await expectLater(
        harness.engine.complete(
          sessionId: sessionId,
          lines: bogus,
          nowUtc: testNow,
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.invalidCompletionLine,
          ),
        ),
      );
      expect(await harness.allEvents(), isEmpty);
    });

    test('completing an abandoned session is rejected', () async {
      final sessionId = await reachReview();
      final lines = await harness.engine.review(sessionId: sessionId);
      await harness.engine.abandon(
        sessionId: sessionId,
        confirmed: true,
        nowUtc: testNow,
      );

      await expectLater(
        harness.engine.complete(
          sessionId: sessionId,
          lines: lines,
          nowUtc: testNow,
        ),
        throwsA(
          isA<EngineException>().having(
            (error) => error.code,
            'code',
            EngineError.sessionNotActive,
          ),
        ),
      );
      expect(await harness.allEvents(), isEmpty);
    });
  });
}
