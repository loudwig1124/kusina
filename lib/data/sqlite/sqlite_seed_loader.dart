/// Seed loader on SQLite (`docs/08` §4.10): insert the content once, then keep
/// `schema_meta.seed_version` authoritative.
///
/// Reset is one transaction: it refuses while a cook is in progress, deletes the
/// stock events and sessions, and restores the seeded statuses, equipment and
/// kitchen name.
library;

import 'package:sqflite/sqflite.dart';

import '../seed/seed_loader.dart';
import '../seed/seed_source.dart';
import 'app_database.dart';

class SqliteSeedLoader implements SeedLoader {
  SqliteSeedLoader(
    this._db,
    this._source, {
    this.contentSeedVersion = 1,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final Database _db;
  final SeedSource _source;
  final int contentSeedVersion;
  final DateTime Function() _clock;

  static const int _kitchenId = 1;

  @override
  Future<void> seedIfNeeded() async {
    if (await seedVersion() >= contentSeedVersion) {
      return;
    }
    final data = await _source.load();
    await _db.transaction((txn) async {
      for (final entry in data.tables) {
        for (final row in entry.rows) {
          await txn.insert(entry.table, row);
        }
      }
      await txn.update('schema_meta', <String, Object?>{
        'seed_version': contentSeedVersion,
        'updated_at': isoUtc(_clock()),
      }, where: 'id = 1');
    });
  }

  @override
  Future<int> schemaVersion() async {
    final rows = await _db.query(
      'schema_meta',
      columns: <String>['schema_version'],
      where: 'id = 1',
    );
    return rows.single['schema_version']! as int;
  }

  @override
  Future<int> seedVersion() async {
    final rows = await _db.query(
      'schema_meta',
      columns: <String>['seed_version'],
      where: 'id = 1',
    );
    return rows.single['seed_version']! as int;
  }

  @override
  Future<void> resetDemoData() async {
    final data = await _source.load();
    await _db.transaction((txn) async {
      final active = await txn.query(
        'cooking_sessions',
        columns: <String>['id'],
        where: 'status = ?',
        whereArgs: <Object?>['in_progress'],
        limit: 1,
      );
      if (active.isNotEmpty) {
        throw StateError(
          'a cook is in progress (session ${active.single['id']}): '
          'finish or abandon it before resetting demo data',
        );
      }
      final now = isoUtc(_clock());
      await txn.delete('stock_event');
      await txn.delete('cooking_sessions');
      for (final row in data.stockStatus) {
        await txn.update(
          'stock_status',
          <String, Object?>{'status': row['status'], 'updated_at': now},
          where: 'kitchen_id = ? AND ingredient_id = ?',
          whereArgs: <Object?>[_kitchenId, row['ingredient_id']],
        );
      }
      await txn.delete(
        'kitchen_equipment',
        where: 'kitchen_id = ?',
        whereArgs: <Object?>[_kitchenId],
      );
      for (final row in data.kitchenEquipment) {
        await txn.insert('kitchen_equipment', row);
      }
      for (final row in data.kitchens) {
        await txn.update(
          'kitchens',
          <String, Object?>{'name': row['name'], 'updated_at': now},
          where: 'id = ?',
          whereArgs: <Object?>[_kitchenId],
        );
      }
      await txn.update('schema_meta', <String, Object?>{
        'seed_version': contentSeedVersion,
        'updated_at': now,
      }, where: 'id = 1');
    });
  }
}
