import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';
import 'package:kusina/features/guide/guide_screen.dart';
import 'package:kusina/features/recipes/recipe_detail_screen.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';
import 'package:kusina/ui/pixel/pixel_method_control.dart';

import '../helpers/assertions.dart';
import '../helpers/fixture_harness.dart';

void main() {
  List<AvailabilityState> panelStates(WidgetTester tester) => tester
      .widgetList<PixelAvailabilityBadge>(find.byType(PixelAvailabilityBadge))
      .map((badge) => badge.state)
      .toList();

  group('default kitchen (owns stovetop + air fryer)', () {
    testWidgets('nothing is preselected and Start stays disabled', (
      tester,
    ) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      final control = tester.widget<PixelMethodControl>(
        find.byType(PixelMethodControl),
      );
      expect(control.selectedKey, isNull);
      expect(control.options, hasLength(2));
      expect(control.options.map((option) => option.label), <String>[
        'Pan-fry',
        'Air-fry',
      ]);

      // No panel badge before the cook picks; the prompt is the primary copy.
      expect(panelStates(tester), isEmpty);
      expect(find.text('CHOOSE PAN-FRY OR AIR-FRY'), findsOneWidget);
      expect(
        tester
            .widget<PixelButton>(
              find.widgetWithText(PixelButton, 'CHOOSE PAN-FRY OR AIR-FRY'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Choose Pan-fry or Air-fry to see what you need.'),
        findsOneWidget,
      );
      expectNoNumericInputs(tester);
    });

    testWidgets('picking Air-fry re-evaluates panel and start action', (
      tester,
    ) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      await tester.tap(find.text('Air-fry'));
      await tester.pumpAndSettle();

      expect(panelStates(tester), <AvailabilityState>[AvailabilityState.ready]);
      expect(find.text('START COOKING'), findsOneWidget);
      expect(find.text('Starts on the Air-fry method.'), findsOneWidget);
      expect(
        tester
            .widget<PixelMethodControl>(find.byType(PixelMethodControl))
            .selectedKey,
        'air_fry',
      );
    });

    testWidgets('picking Pan-fry swaps the pick and keeps the panel honest', (
      tester,
    ) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      await tester.tap(find.text('Air-fry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pan-fry'));
      await tester.pumpAndSettle();

      expect(panelStates(tester), <AvailabilityState>[AvailabilityState.ready]);
      expect(find.text('Starts on the Pan-fry method.'), findsOneWidget);
      expect(
        tester
            .widget<PixelMethodControl>(find.byType(PixelMethodControl))
            .selectedKey,
        'pan_fry',
      );
    });

    testWidgets('the two methods keep their own badges on one screen', (
      tester,
    ) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      final control = tester.widget<PixelMethodControl>(
        find.byType(PixelMethodControl),
      );
      expect(control.options[0].availability, AvailabilityState.ready);
      expect(control.options[1].availability, AvailabilityState.ready);
    });
  });

  group('per-method availability', () {
    testWidgets('without the air fryer: Air-fry is Missing, Pan-fry is Ready', (
      tester,
    ) async {
      final harness = await createHarness(ownedEquipment: <String>{'stovetop'});
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      final control = tester.widget<PixelMethodControl>(
        find.byType(PixelMethodControl),
      );
      expect(control.options[0].availability, AvailabilityState.ready);
      expect(control.options[1].availability, AvailabilityState.blocked);

      await tester.tap(find.text('Air-fry'));
      await tester.pumpAndSettle();
      expect(panelStates(tester), <AvailabilityState>[
        AvailabilityState.blocked,
      ]);
      expect(find.text('Air Fryer is missing.'), findsOneWidget);
      expect(find.text('GUIDE ME ANYWAY'), findsOneWidget);

      await tester.tap(find.text('Pan-fry'));
      await tester.pumpAndSettle();
      expect(panelStates(tester), <AvailabilityState>[AvailabilityState.ready]);
      expect(find.text('START COOKING'), findsOneWidget);
    });

    testWidgets('without the stovetop: both methods go Missing for the pick', (
      tester,
    ) async {
      final harness = await createHarness(
        ownedEquipment: <String>{'air_fryer'},
      );
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      await tester.tap(find.text('Pan-fry'));
      await tester.pumpAndSettle();
      expect(panelStates(tester), <AvailabilityState>[
        AvailabilityState.blocked,
      ]);
      expect(find.text('Stovetop is missing.'), findsOneWidget);

      await tester.tap(find.text('Air-fry'));
      await tester.pumpAndSettle();
      expect(find.text('Stovetop is missing.'), findsOneWidget);
      expect(find.text('GUIDE ME ANYWAY'), findsOneWidget);
    });

    testWidgets('a blocked pick starts only through the confirm sheet', (
      tester,
    ) async {
      final harness = await createHarness(ownedEquipment: <String>{'stovetop'});
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      await tester.tap(find.text('Air-fry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GUIDE ME ANYWAY'));
      await tester.pumpAndSettle();

      // The sheet names every missing requirement.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('START ANYWAY?'), findsOneWidget);
      expect(find.textContaining('Air Fryer is missing.'), findsWidgets);

      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(PixelButton, 'GUIDE ME ANYWAY'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.text('STARTED ANYWAY'), findsOneWidget);
      expect(find.textContaining('equipment:air_fryer'), findsOneWidget);
      expect(find.textContaining('Air-fry method'), findsOneWidget);
    });

    testWidgets('cancelling the confirm sheet does not start', (tester) async {
      final harness = await createHarness(ownedEquipment: <String>{'stovetop'});
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/crispy-pork-belly',
      );

      await tester.tap(find.text('Air-fry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GUIDE ME ANYWAY'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(PixelButton, 'CANCEL'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
    });
  });

  group('single-path dish', () {
    testWidgets(
      'Adobo hides the method control and shows the missing bay leaf',
      (tester) async {
        final harness = await createHarness();
        await pumpKusinaApp(
          tester,
          harness,
          initialLocation: '/recipes/chicken-adobo',
        );

        expect(find.byType(PixelMethodControl), findsNothing);
        expect(find.text('COOKING METHOD'), findsNothing);
        expect(panelStates(tester), <AvailabilityState>[
          AvailabilityState.blocked,
        ]);
        expect(find.text('Bay leaf is out of stock.'), findsOneWidget);
        expect(find.text('1 MISSING ITEM'), findsOneWidget);
        expect(find.text('GUIDE ME ANYWAY'), findsOneWidget);
        expect(find.text('Base yield: 4 servings'), findsOneWidget);
        expectNoNumericInputs(tester);
      },
    );

    testWidgets('Adobo is Ready once the bay leaf is restocked', (
      tester,
    ) async {
      final harness = await createHarness(
        statuses: <String, StockStatus>{
          ...(await createHarness()).statuses,
          'bay_leaf': StockStatus.have,
        },
      );
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/chicken-adobo',
      );

      expect(panelStates(tester), <AvailabilityState>[AvailabilityState.ready]);
      expect(find.text('START COOKING'), findsOneWidget);
    });

    testWidgets('a low required ingredient warns without blocking', (
      tester,
    ) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: '/recipes/chicken-adobo',
      );
      // Demo kitchen: spring onion is low but optional for Adobo, so the panel
      // stays blocked on the bay leaf and never names the optional line.
      expect(
        find.text('Optional (3): cooking oil, black pepper, + 1 more'),
        findsOneWidget,
      );
      expect(find.textContaining('You may run short'), findsNothing);
    });
  });
}
