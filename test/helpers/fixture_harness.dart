/// Test harness: loads the real `assets/fixtures/` content from disk (so tests
/// prove the shipped JSON, not a copy), builds the Phase A repository bundle and
/// pumps the app on a phone-sized surface.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/app.dart';
import 'package:kusina/app/di.dart';
import 'package:kusina/data/repositories/fixture/fixture_bundle.dart';
import 'package:kusina/data/repositories/fixture/fixture_data.dart';
import 'package:kusina/data/repositories/fixture/fixture_equipment_repository.dart';
import 'package:kusina/data/repositories/fixture/fixture_kitchen_repository.dart';
import 'package:kusina/data/repositories/fixture/fixture_recipe_repository.dart';
import 'package:kusina/data/repositories/fixture/fixture_seed_loader.dart';
import 'package:kusina/data/repositories/fixture/fixture_source.dart';
import 'package:kusina/data/repositories/fixture/fixture_stock_repository.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/availability_service.dart';

/// Reads the fixture JSON from the repository instead of the asset bundle, so a
/// test failure points at the content file.
class DiskFixtureSource implements FixtureSource {
  const DiskFixtureSource([this.root = 'assets/fixtures']);

  final String root;

  @override
  Future<Map<String, String>> load() async {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      throw StateError(
        'fixture directory "$root" is missing; run tests from Final Project/',
      );
    }
    final files = <String, String>{};
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.json')) {
        files[entity.path] = entity.readAsStringSync();
      }
    }
    return files;
  }
}

/// A repository bundle plus the mutable fixture state behind it.
class FixtureHarness {
  FixtureHarness({
    required this.bundle,
    required this.data,
    required this.repositories,
  });

  final FixtureBundle bundle;
  final FixtureData data;
  final Repositories repositories;

  /// Demo equipment minus whatever the test removed.
  Set<String> get ownedEquipmentCodes =>
      Set<String>.of(data.ownedEquipmentCodes);

  Map<String, StockStatus> get statuses =>
      Map<String, StockStatus>.of(data.statuses);

  Future<void> setOwned(Set<String> codes) =>
      FixtureEquipmentRepository(data).setOwned(codes);
}

/// Fixed clock: timestamps never make a test flaky.
DateTime fixedClock() => DateTime.utc(2026, 1, 1, 9);

Future<FixtureBundle> loadFixtureBundle() async =>
    FixtureBundle.parse(await const DiskFixtureSource().load());

/// Builds the repository bundle with optional equipment/stock overrides.
Future<FixtureHarness> createHarness({
  Set<String>? ownedEquipment,
  Map<String, StockStatus>? statuses,
  Map<String, String>? extraFiles,
}) async {
  final files = <String, String>{...await const DiskFixtureSource().load()};
  if (extraFiles != null) {
    files.addAll(extraFiles);
  }
  final bundle = FixtureBundle.parse(files);
  final data = FixtureData(bundle: bundle, clock: fixedClock);
  if (ownedEquipment != null) {
    await FixtureEquipmentRepository(data).setOwned(ownedEquipment);
  }
  if (statuses != null) {
    data.statuses
      ..clear()
      ..addAll(statuses);
  }
  final repositories = Repositories(
    recipes: FixtureRecipeRepository(bundle),
    stock: FixtureStockRepository(data),
    equipment: FixtureEquipmentRepository(data),
    kitchen: FixtureKitchenRepository(data),
    seedLoader: FixtureSeedLoader(data),
    availability: const PresenceAvailabilityService(),
    kitchenConfigured: true,
  );
  return FixtureHarness(bundle: bundle, data: data, repositories: repositories);
}

/// A 360 dp wide phone. Tall by default so list content is built without
/// scroll-hunting; individual tests can pass a shorter height.
void setPhoneSurface(WidgetTester tester, {double height = 1600}) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = Size(360 * 3, height * 3);
  addTearDown(tester.view.reset);
}

/// Pumps the real app shell against an arbitrary repository bundle (SQLite
/// tests use this: the app is the same, only the ports change).
Future<void> pumpKusinaAppWithRepositories(
  WidgetTester tester,
  Repositories repositories, {
  String initialLocation = '/',
  double height = 1600,
  DateTime Function()? clock,
  bool settle = true,
}) async {
  setPhoneSurface(tester, height: height);
  await tester.pumpWidget(
    KusinaApp(
      key: UniqueKey(),
      repositories: repositories,
      initialLocation: initialLocation,
      clock: clock,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A running countdown schedules a frame every second, so `pumpAndSettle`
    // would never return; pump a couple of frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps the real app shell against the harness repositories.
Future<void> pumpKusinaApp(
  WidgetTester tester,
  FixtureHarness harness, {
  String initialLocation = '/',
  double height = 1600,
  DateTime Function()? clock,
}) async {
  setPhoneSurface(tester, height: height);
  await tester.pumpWidget(
    KusinaApp(
      // A fresh key each pump: a second pump in one test must build a new app
      // (and therefore a new router with the new initialLocation) instead of
      // reusing the previous State.
      key: UniqueKey(),
      repositories: harness.repositories,
      initialLocation: initialLocation,
      clock: clock,
    ),
  );
  await tester.pumpAndSettle();
}
