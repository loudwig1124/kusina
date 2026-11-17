import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/guide/guide_models.dart';
import 'package:kusina/domain/guide/guide_rules.dart';
import 'package:kusina/domain/models/stock.dart';

void main() {
  group('timer derivation (docs/09 T-21..T-25, T-58)', () {
    final started = DateTime.utc(2026, 1, 1, 9);

    test('T-21 running: remaining is derived from the absolute start', () {
      final timer = deriveTimer(
        timerStartedAtUtc: started,
        timerDurationSeconds: 1500,
        nowUtc: started.add(const Duration(seconds: 600)),
        lastSeenAtUtc: started,
      );

      expect(timer.phase, TimerPhase.running);
      expect(timer.remaining, const Duration(seconds: 900));
      expect(timer.clockSkewDetected, isFalse);
      expect(timerCopy(timer), '15:00 left');
    });

    test('T-22 done when the deadline was crossed while foreground', () {
      final deadline = started.add(const Duration(seconds: 300));
      final timer = deriveTimer(
        timerStartedAtUtc: started,
        timerDurationSeconds: 300,
        nowUtc: deadline,
        lastSeenAtUtc: deadline,
      );

      expect(timer.phase, TimerPhase.done);
      expect(timer.remaining, Duration.zero);
      expect(timer.overdue, Duration.zero);
      expect(timerCopy(timer), 'Timer done.');
    });

    test('T-23 overrun when it ended while the cook was away', () {
      final timer = deriveTimer(
        timerStartedAtUtc: started,
        timerDurationSeconds: 300,
        nowUtc: started.add(const Duration(seconds: 360)),
        lastSeenAtUtc: started,
      );

      expect(timer.phase, TimerPhase.overrun);
      expect(timer.overdue, const Duration(seconds: 60));
      expect(timerCopy(timer), 'Timer finished 1 min ago.');
    });

    test('T-24 a backwards clock caps the remaining time', () {
      final timer = deriveTimer(
        timerStartedAtUtc: started,
        timerDurationSeconds: 300,
        nowUtc: started.subtract(const Duration(hours: 2)),
        lastSeenAtUtc: started,
      );

      expect(timer.phase, TimerPhase.running);
      expect(timer.remaining, const Duration(seconds: 300));
      expect(timer.clockSkewDetected, isTrue);
    });

    test('T-25 a forward jump shows overrun with the real gap', () {
      final timer = deriveTimer(
        timerStartedAtUtc: started,
        timerDurationSeconds: 300,
        nowUtc: started.add(const Duration(seconds: 3900)),
        lastSeenAtUtc: started,
      );

      expect(timer.phase, TimerPhase.overrun);
      expect(timer.overdue, const Duration(seconds: 3600));
    });

    test('T-58 UTC arithmetic ignores a local DST change', () {
      // 2026-03-08 10:00Z is after the US spring-forward; the engine works in
      // UTC so the deadline is exact.
      final dstStart = DateTime.utc(2026, 3, 8, 9, 0);
      final timer = deriveTimer(
        timerStartedAtUtc: dstStart,
        timerDurationSeconds: 3600,
        nowUtc: dstStart.add(const Duration(minutes: 30)),
        lastSeenAtUtc: dstStart,
      );
      expect(timer.remaining, const Duration(minutes: 30));

      final ended = deriveTimer(
        timerStartedAtUtc: dstStart,
        timerDurationSeconds: 3600,
        nowUtc: dstStart.add(const Duration(hours: 2)),
        lastSeenAtUtc: dstStart,
      );
      expect(ended.phase, TimerPhase.overrun);
      expect(ended.overdue, const Duration(hours: 1));
    });

    test('no timer is idle, never a running countdown', () {
      final timer = deriveTimer(
        timerStartedAtUtc: null,
        timerDurationSeconds: null,
        nowUtc: started,
        lastSeenAtUtc: null,
      );

      expect(timer.phase, TimerPhase.idle);
      expect(timer.hasEnded, isFalse);
      expect(timerCopy(timer), isEmpty);
    });

    test('a zero duration behaves like no timer', () {
      final timer = deriveTimer(
        timerStartedAtUtc: started,
        timerDurationSeconds: 0,
        nowUtc: started,
        lastSeenAtUtc: started,
      );
      expect(timer.phase, TimerPhase.idle);
    });
  });

  group('progress (docs/09 T-30..T-33)', () {
    test('T-30 step 3 of 7 is 28%', () {
      expect(completedSteps(3, 7), 2);
      expect(progressPercent(3, 7), 28);
      expect(progressFraction(3, 7), closeTo(2 / 7, 1e-9));
    });

    test('T-31 the review sentinel is 100% and still in progress', () {
      expect(completedSteps(8, 7), 7);
      expect(progressPercent(8, 7), 100);
    });

    test('T-32 a one-step recipe goes 0% -> 100%', () {
      expect(progressPercent(1, 1), 0);
      expect(progressPercent(2, 1), 100);
    });

    test('progress never exceeds 100% or drops below 0%', () {
      expect(progressPercent(0, 7), 0);
      expect(progressPercent(99, 7), 100);
    });
  });

  group('review choices (docs/09 §8.1/§8.2)', () {
    test('exactly three choices, two when the line is out', () {
      expect(allowedChoicesFor(StockStatus.have), <CompletionChoice>[
        CompletionChoice.didntUse,
        CompletionChoice.usedIt,
        CompletionChoice.usedItUp,
      ]);
      expect(allowedChoicesFor(StockStatus.out), <CompletionChoice>[
        CompletionChoice.didntUse,
        CompletionChoice.usedItUp,
      ]);
    });

    test('Used it is disabled for out and allowed everywhere else', () {
      expect(
        isChoiceAllowed(StockStatus.out, CompletionChoice.usedIt),
        isFalse,
      );
      for (final status in <StockStatus>[
        StockStatus.have,
        StockStatus.low,
        StockStatus.unknown,
      ]) {
        expect(isChoiceAllowed(status, CompletionChoice.usedIt), isTrue);
      }
      expect(
        isChoiceAllowed(StockStatus.out, CompletionChoice.usedItUp),
        isTrue,
      );
      expect(
        isChoiceAllowed(StockStatus.out, CompletionChoice.didntUse),
        isTrue,
      );
    });

    test('defaults: required have/low use it, everything else doesnt', () {
      expect(
        defaultChoiceFor(status: StockStatus.have, isRequired: true),
        CompletionChoice.usedIt,
      );
      expect(
        defaultChoiceFor(status: StockStatus.low, isRequired: true),
        CompletionChoice.usedIt,
      );
      expect(
        defaultChoiceFor(status: StockStatus.unknown, isRequired: true),
        CompletionChoice.didntUse,
      );
      expect(
        defaultChoiceFor(status: StockStatus.out, isRequired: true),
        CompletionChoice.didntUse,
      );
      expect(
        defaultChoiceFor(status: StockStatus.have, isRequired: false),
        CompletionChoice.didntUse,
      );
    });
  });

  group('transition table (docs/09 T-52)', () {
    const expected = <String, List<String>>{
      'have|didntUse': <String>[],
      'have|usedIt': <String>['have->low:used_some:linked'],
      'have|usedItUp': <String>['have->out:used_up:linked'],
      'low|didntUse': <String>[],
      'low|usedIt': <String>[],
      'low|usedItUp': <String>['low->out:used_up:linked'],
      'unknown|didntUse': <String>[],
      'unknown|usedIt': <String>['unknown->low:used_some:linked'],
      'unknown|usedItUp': <String>['unknown->out:used_up:linked'],
      'out|didntUse': <String>[],
      'out|usedItUp': <String>[],
      // out + usedIt is invalid; the engine rejects it before this function.
      'out|usedIt': <String>[],
    };

    for (final status in StockStatus.values) {
      for (final choice in CompletionChoice.values) {
        test('$status + ${choice.name}', () {
          final transitions = completionTransitionsFor(
            ingredientCode: 'salt',
            current: status,
            choice: choice,
          );
          final actual = <String>[
            for (final transition in transitions)
              '${transition.from.wireCode}->${transition.to.wireCode}:'
                  '${transition.reason.wireCode}:'
                  '${transition.sessionLinked ? 'linked' : 'unlinked'}',
          ];
          expect(
            actual,
            expected['${status.wireCode}|${choice.name}']!,
            reason: 'docs/09 §8.3 mapping',
          );
          for (final transition in transitions) {
            expect(
              transition.ingredientCode,
              'salt',
              reason: 'the transition keeps the line identity',
            );
          }
        });
      }
    }

    test('the restock correction chains before the usage transition', () {
      final fromUnknown = completionTransitionsFor(
        ingredientCode: 'salt',
        current: StockStatus.unknown,
        choice: CompletionChoice.usedIt,
        restockToHave: true,
      );
      expect(
        <String>[
          for (final transition in fromUnknown) transition.reason.wireCode,
        ],
        <String>['restock', 'used_some'],
      );
      expect(
        <String>[
          for (final transition in fromUnknown)
            transition.sessionLinked.toString(),
        ],
        <String>['false', 'true'],
      );

      final fromOut = completionTransitionsFor(
        ingredientCode: 'salt',
        current: StockStatus.out,
        choice: CompletionChoice.usedItUp,
        restockToHave: true,
      );
      expect(
        <String>[for (final transition in fromOut) transition.to.wireCode],
        <String>['have', 'out'],
      );

      final alreadyHave = completionTransitionsFor(
        ingredientCode: 'salt',
        current: StockStatus.have,
        choice: CompletionChoice.didntUse,
        restockToHave: true,
      );
      expect(alreadyHave, isEmpty);
    });
  });

  group('copy', () {
    test('countdown is mm:ss', () {
      expect(formatCountdown(const Duration(minutes: 25)), '25:00');
      expect(formatCountdown(const Duration(seconds: 59)), '00:59');
      expect(formatCountdown(Duration.zero), '00:00');
    });

    test('away copy rounds down to one unit', () {
      expect(formatAway(const Duration(seconds: 30)), 'less than a minute');
      expect(formatAway(const Duration(minutes: 4, seconds: 30)), '4 min');
      expect(formatAway(const Duration(hours: 3, minutes: 5)), '3 hr');
      expect(formatAway(const Duration(hours: 30)), 'more than a day');
    });
  });
}
