/// SQLite test harness: a real file database built from the shipped DDL and
/// the seeded content, both read from disk so the tests prove the artifacts.
library;

import 'dart:io';

import 'package:kusina/app/di.dart';
import 'package:kusina/data/repositories/session_repository.dart';
import 'package:kusina/data/seed/ingredient_gloss_source.dart';
import 'package:kusina/data/seed/seed_source.dart';
import 'package:kusina/data/sqlite/app_database.dart';
import 'package:kusina/data/sqlite/sqlite_guide_store.dart';
import 'package:kusina/data/sqlite/sqlite_seed_loader.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime fixedSqliteClock() => DateTime.utc(2026, 1, 1, 9);

/// Reads the shipped schema artifact from the repository (not a copy).
Future<String> diskSchemaLoader() =>
    File('db/schema-sqlite.sql').readAsString();

/// Reads the shipped seed JSON from `assets/seed/`.
class DiskSeedSource implements SeedSource {
  const DiskSeedSource();

  @override
  Future<SeedDataSet> load() async {
    final files = <String, String>{};
    for (final name in seedFileNames) {
      files[name] = await File('assets/seed/$name').readAsString();
    }
    return parseSeedFiles(files);
  }
}

/// Fixture catalog glosses, read from disk for plain (non-binding) tests.
Future<Map<String, String>> diskIngredientGlosses() async =>
    parseIngredientGlosses(
      await File('assets/fixtures/ingredients.json').readAsString(),
    );

class SqliteHarness {
  SqliteHarness({
    required this.database,
    required this.repositories,
    required this.directory,
    required this.path,
  });

  final AppDatabase database;
  final Repositories repositories;
  final Directory directory;
  final String path;

  SqliteGuideStore get guideStore =>
      repositories.guideStore! as SqliteGuideStore;

  SessionRepository get sessions => repositories.sessions!;

  SqliteSeedLoader get seedLoader =>
      repositories.seedLoader as SqliteSeedLoader;

  Database get db => database.database;

  Future<void> dispose() async {
    await database.close();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// Opens a fresh seeded database in a temp directory.
Future<SqliteHarness> createSqliteHarness({
  bool seed = true,
  String fileName = 'kusina.db',
}) async {
  sqfliteFfiInit();
  final directory = Directory.systemTemp.createTempSync('kusina_sqlite_');
  final path = '${directory.path}/$fileName';
  final database = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
    schemaLoader: diskSchemaLoader,
  );
  final repositories = await Repositories.sqlite(
    database: database.database,
    schemaLoader: diskSchemaLoader,
    seedSource: const DiskSeedSource(),
    ingredientGlosses: await diskIngredientGlosses(),
    clock: fixedSqliteClock,
    seed: seed,
  );
  return SqliteHarness(
    database: database,
    repositories: repositories,
    directory: directory,
    path: path,
  );
}

/// Closes and reopens the same file: the Phase B cold-start path.
Future<SqliteHarness> reopen(SqliteHarness harness, {bool seed = false}) async {
  await harness.database.close();
  final database = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: harness.path,
    schemaLoader: diskSchemaLoader,
  );
  final repositories = await Repositories.sqlite(
    database: database.database,
    schemaLoader: diskSchemaLoader,
    seedSource: const DiskSeedSource(),
    ingredientGlosses: await diskIngredientGlosses(),
    clock: fixedSqliteClock,
    seed: seed,
  );
  return SqliteHarness(
    database: database,
    repositories: repositories,
    directory: harness.directory,
    path: harness.path,
  );
}

/// Applies the seed-driven demo overrides a test needs.
Future<void> applyStatuses(
  SqliteHarness harness,
  Map<String, StockStatus> statuses,
) async {
  for (final entry in statuses.entries) {
    await harness.repositories.stock.setStatus(
      ingredientCode: entry.key,
      to: entry.value,
      reason: StockReason.correction,
    );
  }
}

/// Tables the frozen schema creates (15).
const List<String> schemaTables = <String>[
  'schema_meta',
  'kitchens',
  'units',
  'ingredients',
  'equipment',
  'kitchen_equipment',
  'stock_status',
  'recipes',
  'recipe_ingredients',
  'recipe_equipment',
  'recipe_steps',
  'recipe_step_variants',
  'cooking_sessions',
  'session_step_choices',
  'stock_event',
];
