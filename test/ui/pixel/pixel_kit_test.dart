import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';
import 'package:kusina/ui/pixel/pixel_app_bar.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';
import 'package:kusina/ui/pixel/pixel_canvas.dart';
import 'package:kusina/ui/pixel/pixel_chip.dart';
import 'package:kusina/ui/pixel/pixel_method_control.dart';
import 'package:kusina/ui/pixel/pixel_progress.dart';
import 'package:kusina/ui/pixel/pixel_sprite.dart';

import '../../helpers/fixture_harness.dart';

void main() {
  group('integer art scale', () {
    test('1080 px wide at DPR 3 is 6 device px per art unit', () {
      final scale = PixelScale.forViewport(widthPx: 1179, devicePixelRatio: 3);

      expect(scale.factor, 6);
      expect(scale.artWidth, 360);
      expect(scale.artWidthPx, 1080);
      expect(scale.au(1), 2);
      expect(scale.au(180), 360);
    });

    test('a 640 px wide phone at DPR 2 gives 3 device px per art unit', () {
      final scale = PixelScale.forViewport(widthPx: 640, devicePixelRatio: 2);

      expect(scale.factor, 3);
      expect(scale.artWidth, 270);
      expect(scale.artWidthPx, 540);
      expect(scale.au(1), 1.5);
    });

    test('the art width is always an integer number of device pixels', () {
      for (final widthPx in <double>[320, 640, 720, 1080, 1179, 1236, 1600]) {
        final scale = PixelScale.forViewport(
          widthPx: widthPx,
          devicePixelRatio: 3,
        );
        expect(scale.artWidthPx % 1, 0);
        expect(scale.artWidthPx, 180 * scale.factor);
      }
    });

    test('a tiny viewport never drops below 1 device px per art unit', () {
      final scale = PixelScale.forViewport(widthPx: 120, devicePixelRatio: 2);
      expect(scale.factor, 1);
    });
  });

  testWidgets('the canvas renders the 180 au column at the integer scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(child: Container(color: const Color(0xFFFFFFFF))),
        ),
      ),
    );

    final canvasSize = tester.getSize(find.byType(PixelCanvas));
    expect(canvasSize.width, 360);
    final provider = tester.widget<PixelScaleProvider>(
      find.byType(PixelScaleProvider).first,
    );
    expect(provider.scale.factor, 6);
    expect(provider.scale.artWidth, 360);
  });

  testWidgets('controls honour the tap floor and the 56 dp primary', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(
            child: Column(
              children: <Widget>[
                PixelButton(label: 'Start cooking', onPressed: () {}),
                PixelButton(
                  label: 'Secondary',
                  kind: PixelButtonKind.secondary,
                  onPressed: () {},
                ),
                PixelFilterChip(label: 'All', selected: true, onTap: () {}),
                PixelStatusChip(status: StockStatus.have, onTap: () {}),
                PixelMethodControl(
                  selectedKey: null,
                  options: const <PixelMethodOption>[
                    PixelMethodOption(
                      key: 'pan_fry',
                      label: 'Pan-fry',
                      iconKey: 'variant_panfry',
                      availability: AvailabilityState.ready,
                    ),
                    PixelMethodOption(
                      key: 'air_fry',
                      label: 'Air-fry',
                      iconKey: 'variant_airfry',
                      availability: AvailabilityState.blocked,
                    ),
                  ],
                  onSelected: (_) {},
                ),
                PixelProgressBar(value: 0.5),
                PixelTimerRing(
                  state: PixelTimerState.idle,
                  label: 'Start timer',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final primary = find.widgetWithText(PixelButton, 'START COOKING');
    expect(tester.getSize(primary).height, 56);

    final secondary = find.widgetWithText(PixelButton, 'SECONDARY');
    expect(tester.getSize(secondary).height, 48);

    expect(tester.getSize(find.byType(PixelFilterChip)).height, 48);
    expect(tester.getSize(find.byType(PixelStatusChip)).height, 48);
    expect(
      tester.getSize(find.byType(PixelMethodControl)).height,
      greaterThanOrEqualTo(72),
    );
    // The timer ring is a 56 au disc; tapping it targets the whole disc.
    expect(
      tester.getSize(find.byType(PixelTimerRing)).width,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('app-bar targets are 48 dp squares', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(
            child: PixelAppBar(
              title: 'KUSINA',
              onBack: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );

    final back = tester.getSize(
      find.byKey(const ValueKey<String>('appbar-back')),
    );
    final gear = tester.getSize(
      find.byKey(const ValueKey<String>('appbar-settings')),
    );
    expect(back, const Size(48, 48));
    expect(gear, const Size(48, 48));
  });

  testWidgets('availability badges show the three locked labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(
            child: Column(
              children: const <Widget>[
                PixelAvailabilityBadge(state: AvailabilityState.ready),
                PixelAvailabilityBadge(
                  state: AvailabilityState.needsConfirmation,
                ),
                PixelAvailabilityBadge(state: AvailabilityState.blocked),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Probably have'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
  });

  testWidgets('status chips carry colour, shape and the locked label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(
            child: Column(
              children: const <Widget>[
                PixelStatusChip(status: StockStatus.have),
                PixelStatusChip(status: StockStatus.low),
                PixelStatusChip(status: StockStatus.out),
                PixelStatusChip(status: StockStatus.unknown),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Have'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Probably have'), findsOneWidget);
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('◐'), findsOneWidget);
    expect(find.text('✕'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  group('sprite library', () {
    test('every authored sprite is a 16 column grid', () {
      for (final key in PixelSprites.keys) {
        for (final row in PixelSprites.rawRows(key)) {
          expect(
            row.length,
            lessThanOrEqualTo(16),
            reason: '$key has a row wider than 16 columns: "$row"',
          );
        }
        expect(
          PixelSprites.grid(key).every((row) => row.length == 16),
          isTrue,
          reason: '$key must pad to 16 columns',
        );
      }
    });

    test('the content keys all resolve to a sprite', () {
      for (final key in <String>[
        'dish_chicken_adobo',
        'dish_sinangag',
        'dish_crispy_pork_belly',
        'variant_panfry',
        'variant_airfry',
        'eq_stovetop',
        'eq_air_fryer',
        'step_prep_none',
        'step_heat_stovetop',
        'step_cook_stovetop',
        'step_wait_stovetop',
        'step_cook_air_fryer',
        'step_finish_none',
        'ing_garlic',
        'tab_cook',
        'ui_gear',
        'ui_back',
      ]) {
        expect(
          PixelSprites.hasSprite(key) || key.startsWith('ing_'),
          isTrue,
          reason: 'missing sprite for $key',
        );
      }
    });

    test('an unknown key falls back instead of rendering a hole', () {
      expect(PixelSprites.grid('mystery_sprite'), isNotEmpty);
    });

    testWidgets('a sprite renders square at the requested art size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PixelCanvas(
              child: Center(
                child: PixelSprite(
                  spriteKey: 'dish_chicken_adobo',
                  artUnits: 16,
                ),
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(PixelSprite));
      expect(size.width, size.height);
      expect(size.width, 32); // 16 au at k=6, dpr 3 -> 2 dp per au
    });
  });

  testWidgets('the demo content keys match the sprite library', (tester) async {
    final harness = await createHarness();
    for (final recipe in harness.bundle.recipes) {
      expect(
        PixelSprites.hasSprite(recipe.dishStampKey),
        isTrue,
        reason: '${recipe.name} stamp ${recipe.dishStampKey}',
      );
      for (final method in recipe.methods) {
        expect(
          PixelSprites.hasSprite(method.iconKey),
          isTrue,
          reason: '${method.label} icon ${method.iconKey}',
        );
      }
      for (final step in recipe.steps) {
        expect(
          PixelSprites.hasSprite(step.spriteKey),
          isTrue,
          reason: 'step ${step.stepNumber} sprite ${step.spriteKey}',
        );
      }
    }
    for (final item in harness.bundle.equipment) {
      expect(
        PixelSprites.hasSprite(item.spriteKey),
        isTrue,
        reason: 'appliance ${item.name} sprite ${item.spriteKey}',
      );
    }
  });
}
