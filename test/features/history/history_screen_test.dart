import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/features/history/history_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../../helpers/fixture_harness.dart';
import '../guide/guide_test_helpers.dart';

void main() {
  testWidgets('History lists a completed cook with its stock events', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('1 COOK'), findsOneWidget);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    // The row expands in place (no new route) and lists the linked events.
    await tester.tap(find.text('SHOW CHANGES (TAP)'));
    await tester.pumpAndSettle();
    expect(find.text('HIDE CHANGES (TAP)'), findsOneWidget);
    expect(
      find.textContaining('chicken thighs: Have → Low · used some'),
      findsOneWidget,
    );
    expect(find.textContaining('bay leaf'), findsNothing);
  });

  testWidgets('an abandoned cook appears with no stock events', (tester) async {
    final harness = await createHarness();
    await openAdoboGuide(tester, harness);

    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'ABANDON COOK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();

    expect(find.text('Abandoned'), findsOneWidget);
    await tester.tap(find.text('SHOW CHANGES (TAP)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Abandoned cooks write no stock changes.'),
      findsOneWidget,
    );
  });

  testWidgets('a review restock appears in the Stock events segment', (
    tester,
  ) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);

    // "I have it" on the out bay leaf; leave the choice at Didn't use.
    await tester.tap(find.byKey(const ValueKey('review-restock-bay_leaf')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'CONFIRM'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'BACK TO COOK NOW'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock events'));
    await tester.pumpAndSettle();

    expect(find.text('5 EVENTS'), findsOneWidget);
    expect(find.text('bay leaf'), findsOneWidget);
    expect(find.textContaining('Out → Have · restocked'), findsOneWidget);
    // The review restock is deliberately unlinked; the segment still shows it.
    expect(find.text('review note (no cook link)'), findsOneWidget);
    expect(find.text('linked to a cook'), findsNWidgets(4));
  });

  testWidgets('History is empty before any cook', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/history');

    expect(find.text('No cooks yet. Start with Cook now.'), findsOneWidget);
    expect(find.text('0 COOKS'), findsOneWidget);
  });

  testWidgets('Reset after a completed cook restores the demo', (tester) async {
    final harness = await createHarness();
    await openAdoboReview(tester, harness);
    await confirmReview(tester);

    await tester.tap(find.byKey(const ValueKey<String>('appbar-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PixelButton, 'RESET DEMO DATA'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(PixelButton, 'RESET'),
      ),
    );
    await tester.pumpAndSettle();

    // The demo statuses came back and the history was cleared.
    await tester.tap(find.byKey(const ValueKey<String>('appbar-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('No cooks yet. Start with Cook now.'), findsOneWidget);
  });
}
