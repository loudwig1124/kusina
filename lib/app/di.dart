/// Composition root: the only file that names concrete repositories
/// (`docs/08` §3 layer rule 4, §6.3).
///
/// Phase A builds the fixture set from the bundled `assets/fixtures/` JSON.
/// Phase B builds the same ports over SQLite (`Repositories.sqlite`), applying
/// the bundled DDL, seeding the t4 rows once and handing back the guide store —
/// screens, domain rules and the router are identical for both.
library;

import 'package:sqflite/sqflite.dart';

import '../data/repositories/equipment_repository.dart';
import '../data/repositories/fixture/fixture_bundle.dart';
import '../data/repositories/fixture/fixture_data.dart';
import '../data/repositories/fixture/fixture_equipment_repository.dart';
import '../data/repositories/fixture/fixture_kitchen_repository.dart';
import '../data/repositories/fixture/fixture_recipe_repository.dart';
import '../data/repositories/fixture/fixture_seed_loader.dart';
import '../data/repositories/fixture/fixture_source.dart';
import '../data/repositories/fixture/fixture_stock_repository.dart';
import '../data/repositories/kitchen_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/stock_repository.dart';
import '../data/seed/ingredient_gloss_source.dart';
import '../data/seed/seed_loader.dart';
import '../data/seed/seed_source.dart';
import '../data/sqlite/app_database.dart';
import '../data/sqlite/schema_asset.dart';
import '../data/sqlite/sqlite_equipment_repository.dart';
import '../data/sqlite/sqlite_guide_store.dart';
import '../data/sqlite/sqlite_kitchen_repository.dart';
import '../data/sqlite/sqlite_recipe_repository.dart';
import '../data/sqlite/sqlite_seed_loader.dart';
import '../data/sqlite/sqlite_stock_repository.dart';
import '../domain/guide/guide_store.dart';
import '../domain/rules/availability_service.dart';

/// The repository bundle handed to [AppScope].
class Repositories {
  Repositories({
    required this.recipes,
    required this.stock,
    required this.equipment,
    required this.kitchen,
    required this.seedLoader,
    required this.availability,
    required this.kitchenConfigured,
    this.guideStore,
    this.sessions,
  });

  final RecipeRepository recipes;
  final StockRepository stock;
  final EquipmentRepository equipment;
  final KitchenRepository kitchen;
  final SeedLoader seedLoader;

  /// Pure rule object; shared by every availability read.
  final AvailabilityService availability;

  /// False only on the very first launch, before the demo kitchen is seeded.
  /// The router redirects `/` to `/setup` while it is false; every later launch
  /// (fixture or SQLite) reports true.
  ///
  /// Mutable on purpose: setup writes the kitchen row and then flips this flag
  /// before navigating, so the redirect does not bounce the cook back to
  /// `/setup` with a value captured at process start.
  bool kitchenConfigured;

  /// Phase B: the SQLite-backed guide store (sessions + pinned path +
  /// completion transaction). Null for the fixture bundle, which builds its
  /// in-memory store from the repositories above.
  final GuideStore? guideStore;

  /// Read-side session view over the same database.
  final SessionRepository? sessions;

  /// Builds the Phase A fixture set from the bundled content JSON.
  static Future<Repositories> fixtures({
    FixtureSource source = const AssetFixtureSource(),
    Clock? clock,
  }) async {
    final bundle = FixtureBundle.parse(await source.load());
    final data = FixtureData(bundle: bundle, clock: clock);
    return Repositories(
      recipes: FixtureRecipeRepository(bundle),
      stock: FixtureStockRepository(data),
      equipment: FixtureEquipmentRepository(data),
      kitchen: FixtureKitchenRepository(data),
      seedLoader: FixtureSeedLoader(data),
      availability: const PresenceAvailabilityService(),
      kitchenConfigured: true,
    );
  }

  /// Builds the Phase B SQLite set: open the database, apply the bundled DDL,
  /// seed once, then expose the same ports.
  ///
  /// Pass [factory] and [path] to run against a temp database (tests); pass
  /// [database] when the caller already opened it and wants to keep it.
  static Future<Repositories> sqlite({
    DatabaseFactory? factory,
    String? path,
    Database? database,
    SchemaLoader schemaLoader = loadSchemaAsset,
    SeedSource seedSource = const AssetSeedSource(),
    Map<String, String>? ingredientGlosses,
    Clock? clock,
    bool seed = true,
  }) async {
    final db =
        database ??
        (await AppDatabase.open(
          factory: factory ?? databaseFactory,
          path: path ?? await defaultDatabasePath(),
          schemaLoader: schemaLoader,
        )).database;
    // A fresh database has no kitchen row yet. Read that *before* seeding, so
    // the first launch shows the setup screen and later launches open Cook now.
    final kitchenRows = await db.query(
      'kitchens',
      columns: <String>['id'],
      limit: 1,
    );
    final kitchenConfigured = kitchenRows.isNotEmpty;
    final seedLoader = SqliteSeedLoader(db, seedSource, clock: clock);
    if (seed) {
      await seedLoader.seedIfNeeded();
    }
    final glosses = ingredientGlosses ?? await loadIngredientGlossesFromAsset();
    final stock = SqliteStockRepository(
      db,
      clock: clock,
      ingredientGlosses: glosses,
    );
    final equipment = SqliteEquipmentRepository(db, clock: clock);
    final recipes = SqliteRecipeRepository(db);
    final guideStore = SqliteGuideStore(
      db,
      recipes: recipes,
      stock: stock,
      equipment: equipment,
      ingredientGlosses: glosses,
      clock: clock,
    );
    return Repositories(
      recipes: recipes,
      stock: stock,
      equipment: equipment,
      kitchen: SqliteKitchenRepository(db, clock: clock),
      seedLoader: seedLoader,
      availability: const PresenceAvailabilityService(),
      kitchenConfigured: kitchenConfigured,
      guideStore: guideStore,
      sessions: guideStore,
    );
  }

  /// Restores the demo kitchen, stock statuses and equipment (Settings).
  Future<void> resetDemoData() => seedLoader.resetDemoData();
}

/// The on-device database file (`kusina.db` in the app's databases directory).
Future<String> defaultDatabasePath() async {
  final directory = await getDatabasesPath();
  return '$directory/kusina.db';
}
