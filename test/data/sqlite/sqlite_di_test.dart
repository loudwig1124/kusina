import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/di.dart';
import 'package:kusina/data/seed/seed_source.dart';
import 'package:kusina/data/sqlite/app_database.dart';
import 'package:kusina/data/sqlite/schema_asset.dart';
import 'package:kusina/data/sqlite/sqlite_guide_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Repositories.sqlite wires the bundled DDL and assets end to end',
    () async {
      sqfliteFfiInit();
      final directory = Directory.systemTemp.createTempSync('kusina_di_');
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final path = '${directory.path}/kusina.db';

      // Exactly what main() would do, but against the bundled artifacts.
      final repositories = await Repositories.sqlite(
        factory: databaseFactoryFfi,
        path: path,
        schemaLoader: loadSchemaAsset,
        seedSource: const AssetSeedSource(),
      );

      // First launch: the kitchen row does not exist yet, so `/setup` shows.
      expect(repositories.kitchenConfigured, isFalse);
      expect(repositories.guideStore, isA<SqliteGuideStore>());
      expect(repositories.sessions, isNotNull);
      expect(
        (await repositories.recipes.listRecipes())
            .map((recipe) => recipe.slug)
            .toList(),
        <String>['chicken-adobo', 'sinangag', 'crispy-pork-belly'],
      );
      final ingredients = await repositories.stock.listIngredients();
      expect(ingredients.length, 15);
      // The gloss survives the SQLite swap: "Garlic (Bawang)", not "Garlic".
      final garlic = ingredients.firstWhere(
        (ingredient) => ingredient.code == 'garlic',
      );
      expect(garlic.label, 'Garlic (Bawang)');
      expect(
        ingredients.map((ingredient) => ingredient.label).toList(),
        contains('Chicken thighs (Hita ng manok)'),
      );
      expect((await repositories.equipment.catalog()).length, 5);
      expect((await repositories.equipment.ownedIds()).length, 2);
      expect((await repositories.kitchen.get()).name, "Maria's Kitchen");
      expect(await repositories.seedLoader.seedVersion(), 1);
      expect(await repositories.seedLoader.schemaVersion(), 1);
      expect(
        await repositories.stock.getStatus('bay_leaf').then((s) => s.name),
        'out',
      );

      // The default on-device path helper is a plain file name in the databases
      // directory; assert it is derived, not hard-coded.
      databaseFactory = databaseFactoryFfi;
      expect(await defaultDatabasePath(), endsWith('kusina.db'));

      await repositories.resetDemoData();

      // Second launch over the same file: the demo kitchen is configured.
      final relaunched = await Repositories.sqlite(
        factory: databaseFactoryFfi,
        path: path,
        schemaLoader: loadSchemaAsset,
        seedSource: const AssetSeedSource(),
      );
      expect(relaunched.kitchenConfigured, isTrue);
      expect((await relaunched.kitchen.get()).name, "Maria's Kitchen");
      await (await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        schemaLoader: loadSchemaAsset,
      )).close();
    },
  );
}
