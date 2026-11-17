/// SQLite bootstrap (`docs/08` §4.10): open the database, enable the pragmas
/// the schema depends on, apply the bundled DDL once and expose the version
/// row.
///
/// Takes an injected [DatabaseFactory] so the app passes sqflite's factory and
/// tests pass `databaseFactoryFfi`; this file imports no Flutter plugin.
library;

import 'package:sqflite/sqflite.dart';

import 'schema_asset.dart';

/// One opened application database plus its version helpers.
class AppDatabase {
  const AppDatabase._(this.database, this.path);

  final Database database;
  final String path;

  /// Opens (and creates) the database.
  ///
  /// `onConfigure` runs `PRAGMA foreign_keys = ON` and a busy timeout on every
  /// connection; `journal_mode = WAL` is applied on open for file databases
  /// (`:memory:` reports `memory` and ignores it). The DDL is applied exactly
  /// once, on creation, from the bundled artifact — no copy, no ORM.
  static Future<AppDatabase> open({
    required DatabaseFactory factory,
    required String path,
    SchemaLoader schemaLoader = loadSchemaAsset,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          final schema = await schemaLoader();
          for (final statement in splitSqlStatements(schema)) {
            await db.execute(statement);
          }
        },
        onOpen: (db) async {
          // WAL is a file-database setting; `:memory:` reports "memory".
          await db.rawQuery('PRAGMA journal_mode = WAL');
        },
      ),
    );
    return AppDatabase._(database, path);
  }

  Future<void> close() => database.close();

  /// `schema_meta.schema_version` (the DDL writes 1).
  Future<int> schemaVersion() async => (await _meta()).schemaVersion;

  /// `schema_meta.seed_version` (0 until the content seed ran).
  Future<int> seedVersion() async => (await _meta()).seedVersion;

  Future<void> setSeedVersion(int seedVersion, DateTime nowUtc) async {
    await database.update('schema_meta', <String, Object?>{
      'seed_version': seedVersion,
      'updated_at': isoUtc(nowUtc),
    }, where: 'id = 1');
  }

  Future<({int schemaVersion, int seedVersion})> _meta() async {
    final rows = await database.query(
      'schema_meta',
      columns: <String>['schema_version', 'seed_version'],
      where: 'id = 1',
    );
    if (rows.isEmpty) {
      throw StateError('schema_meta is empty: the DDL did not run');
    }
    return (
      schemaVersion: rows.single['schema_version']! as int,
      seedVersion: rows.single['seed_version']! as int,
    );
  }
}

/// ISO-8601 UTC with milliseconds, the storage format every timestamp column
/// uses (`docs/06` A5). The DDL's `strftime('%Y-%m-%dT%H:%M:%fZ')` default
/// produces the same shape.
String isoUtc(DateTime value) => value.toUtc().toIso8601String();

/// Parses a stored timestamp back to UTC.
DateTime parseUtc(String value) => DateTime.parse(value).toUtc();
