import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/di.dart';
import 'package:kusina/domain/guide/guide_engine.dart';
import 'package:kusina/domain/guide/guide_models.dart';
import 'package:kusina/features/guide/guide_controller.dart';
import 'package:kusina/features/history/history_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/sqlite/sqlite_harness.dart';

/// The resume card's data path, proven on SQLite across a relaunch.
///
/// Widget-level rendering of the card is covered in `resume_card_test.dart`
/// against the same store seam; this file proves that the session a relaunched
/// app reads is the persisted one (recipe, method, step, timer, missing codes).
void main() {
  test(
    'a relaunched controller rebuilds the resume-card data from SQLite',
    () async {
      sqfliteFfiInit();
      final directory = Directory.systemTemp.createTempSync(
        'kusina_resume_data_',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final path = '${directory.path}/kusina.db';
      final now = DateTime.utc(2026, 1, 1, 9);

      final first = await Repositories.sqlite(
        factory: databaseFactoryFfi,
        path: path,
        schemaLoader: diskSchemaLoader,
        seedSource: const DiskSeedSource(),
        ingredientGlosses: await diskIngredientGlosses(),
        clock: () => now,
      );
      final engine = LocalGuidedCookingEngine(store: first.guideStore!);
      final start = await engine.start(
        recipeSlug: 'crispy-pork-belly',
        methodKey: 'pan_fry',
        guideAnyway: false,
        nowUtc: now,
      );
      final sessionId = start.session!.id;
      await engine.advance(sessionId: sessionId, nowUtc: now);
      await engine.advance(sessionId: sessionId, nowUtc: now);
      await engine.startTimer(sessionId: sessionId, nowUtc: now);

      // "Relaunch": new repository bundle + new controller over the same file.
      final relaunched = await Repositories.sqlite(
        factory: databaseFactoryFfi,
        path: path,
        schemaLoader: diskSchemaLoader,
        seedSource: const DiskSeedSource(),
        ingredientGlosses: await diskIngredientGlosses(),
        clock: () => now.add(const Duration(minutes: 1)),
      );
      final controller = GuideController(
        engine: LocalGuidedCookingEngine(store: relaunched.guideStore!),
        clock: () => now.add(const Duration(minutes: 1)),
      );
      addTearDown(controller.dispose);

      await controller.refreshActiveSession();

      expect(controller.hasActiveSession, isTrue);
      final session = controller.activeSession!;
      expect(session.id, sessionId);
      expect(session.recipeName, 'Crispy Pork Belly');
      expect(session.currentStepNumber, 3);
      expect(session.totalSteps, 6);
      expect(controller.methodLabel, 'Pan-fry method');
      expect(controller.timer.phase, TimerPhase.running);
      expect(controller.timer.remaining, const Duration(minutes: 24));
      expect(controller.stepView!.stepNumber, 3);
      expect(session.path.step(5)!.variantMethodKey, 'pan_fry');

      // Abandoning from the card clears the session and writes no events.
      await controller.abandon();
      expect(controller.hasActiveSession, isFalse);
      expect(await relaunched.stock.listEvents(), isEmpty);

      // History on the relaunched bundle sees the abandoned cook.
      final history = HistoryController(
        sessions: relaunched.guideStore!.sessions,
        stockRepository: relaunched.stock,
      );
      addTearDown(history.dispose);
      await history.load();
      expect(history.entries, hasLength(1));
      expect(history.entries.single.session.status, SessionStatus.abandoned);
      expect(history.entries.single.events, isEmpty);
    },
  );
}
