import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/app_scope.dart';
import 'package:kusina/features/guide/guide_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_progress.dart';

import '../../helpers/fixture_harness.dart';

Future<void> openGuide(WidgetTester tester, FixtureHarness harness) async {
  await tester.tap(find.text('Chicken Adobo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GUIDE ME ANYWAY'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(PixelButton, 'GUIDE ME ANYWAY'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pause persists last_seen_at and resume shows the engine copy', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1, 9);
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, height: 2400, clock: () => now);
    await openGuide(tester, harness);

    final guide = AppScope.of(tester.element(find.byType(GuideScreen))).guide;
    final sessionId = guide.session!.id;

    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    final stored = await guide.engine.session(sessionId);
    expect(
      stored!.lastSeenAtUtc,
      now,
      reason: 'pause writes last_seen_at for done/overrun derivation',
    );
    expect(find.text('WELCOME BACK'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.textContaining('Welcome back. Step 1 of 7.'), findsOneWidget);
    // The step never advanced while away.
    expect(find.text('STEP 1 OF 7'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('WELCOME BACK'), findsNothing);
  });

  testWidgets('leaving the guide releases the wake lock', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, height: 2400);
    await openGuide(tester, harness);

    // Step 2 is the first timed step; starting it arms the wake lock.
    await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
    await tester.pumpAndSettle();
    final guide = AppScope.of(tester.element(find.byType(GuideScreen))).guide;
    await tester.tap(find.byType(PixelTimerRing));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(guide.keepAwakeRequested, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pump();
    await tester.tap(find.widgetWithText(PixelButton, 'LEAVE FOR NOW'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(guide.keepAwakeRequested, isFalse);
    // The session stays in progress; only the wake lock was released.
    expect(guide.hasActiveSession, isTrue);
  });

  testWidgets('the guide renders the scene strip above the step card', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, height: 2400);
    await openGuide(tester, harness);

    expect(find.bySemanticsLabel('step scene'), findsOneWidget);
  });
}
