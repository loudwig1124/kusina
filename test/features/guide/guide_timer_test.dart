import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_progress.dart';

import '../../helpers/fixture_harness.dart';
import 'guide_test_helpers.dart';

void main() {
  testWidgets('the timer starts, renders a countdown and clears', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);

    // Step 2 (heat, 480 s) is the first timed step.
    await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 2 OF 7'), findsOneWidget);
    expect(find.textContaining('Start timer — 8 min'), findsOneWidget);
    expect(find.textContaining('No timer on this step'), findsNothing);

    await tester.tap(find.byType(PixelTimerRing));
    await tester.pumpAndSettle();

    expect(find.textContaining('left'), findsWidgets);

    // Three seconds of ticks later the step has not moved (no auto-advance).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('STEP 2 OF 7'), findsOneWidget);
    expect(find.widgetWithText(PixelButton, 'CONTINUE'), findsOneWidget);

    // Tapping the running ring clears it; there is no pause.
    await tester.tap(find.byType(PixelTimerRing));
    await tester.pumpAndSettle();
    expect(find.textContaining('Start timer — 8 min'), findsOneWidget);
  });

  testWidgets('a step without a timer has no ring action', (tester) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);

    // Step 1 is prep: no timer.
    expect(find.text('No timer on this step'), findsOneWidget);
    expect(find.textContaining('This step has no timer.'), findsOneWidget);

    await tester.tap(find.byType(PixelTimerRing));
    await tester.pumpAndSettle();
    expect(find.textContaining('This step has no timer.'), findsOneWidget);
    expect(find.text('STEP 1 OF 7'), findsOneWidget);
  });

  testWidgets('advancing clears a running timer', (tester) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);
    await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PixelTimerRing));
    await tester.pumpAndSettle();
    expect(find.textContaining('left'), findsWidgets);

    await tester.tap(find.widgetWithText(PixelButton, 'CONTINUE'));
    await tester.pumpAndSettle();

    // Step 3 is untimed, so the ring is idle again.
    expect(find.text('STEP 3 OF 7'), findsOneWidget);
    expect(find.textContaining('This step has no timer.'), findsOneWidget);
  });
}
