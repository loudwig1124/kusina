import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/data/sqlite/schema_asset.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_harness.dart';

void main() {
  late SqliteHarness harness;

  setUp(() async {
    harness = await createSqliteHarness();
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'the shipped DDL creates the 15 tables and the schema_meta row',
    () async {
      final tables = await harness.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final names = tables.map((row) => row['name']! as String).toSet();
      expect(names, containsAll(schemaTables));
      expect(names.length, schemaTables.length);

      final meta = await harness.db.query('schema_meta');
      expect(meta, hasLength(1));
      expect(meta.single['id'], 1);
      expect(meta.single['schema_version'], 1);
      expect(meta.single['seed_version'], 1);
    },
  );

  test('foreign keys are ON and WAL is the journal mode (file DB)', () async {
    final fk = await harness.db.rawQuery('PRAGMA foreign_keys');
    expect(fk.single.values.single, 1);

    final journal = await harness.db.rawQuery('PRAGMA journal_mode');
    expect((journal.single.values.single! as String).toLowerCase(), 'wal');

    final timeout = await harness.db.rawQuery('PRAGMA busy_timeout');
    expect(timeout.single.values.single, 5000);
  });

  test('the indexes the engine relies on exist', () async {
    final rows = await harness.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final names = rows.map((row) => row['name']! as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'uq_cooking_sessions_one_active',
        'uq_stock_event_session_ingredient',
        'idx_stock_status_status',
        'idx_recipe_steps_equipment',
      ]),
    );
  });

  group('schema constraints reject bad rows', () {
    Future<void> expectRejected(Future<void> Function() action) async {
      await expectLater(action(), throwsA(isA<DatabaseException>()));
    }

    test('a foreign key violation is rejected', () async {
      await expectRejected(() async {
        await harness.db.insert('stock_status', <String, Object?>{
          'kitchen_id': 1,
          'ingredient_id': 9999,
          'status': 'have',
        });
      });
    });

    test('stock_event must change the status', () async {
      await expectRejected(() async {
        await harness.db.insert('stock_event', <String, Object?>{
          'ingredient_id': 1,
          'from_status': 'have',
          'to_status': 'have',
          'reason': 'correction',
        });
      });
    });

    test('a reason/transition mismatch is rejected by the DDL', () async {
      await expectRejected(() async {
        await harness.db.insert('stock_event', <String, Object?>{
          'ingredient_id': 1,
          'from_status': 'have',
          'to_status': 'low',
          'reason': 'restock',
        });
      });
    });

    test('a manual event cannot carry a session link', () async {
      await expectRejected(() async {
        await harness.db.insert('stock_event', <String, Object?>{
          'ingredient_id': 1,
          'from_status': 'have',
          'to_status': 'low',
          'reason': 'used_some',
          'cooking_session_id': 1,
        });
      });
    });

    test('a timer needs both columns and an active session', () async {
      await expectRejected(() async {
        await harness.db.insert('cooking_sessions', <String, Object?>{
          'kitchen_id': 1,
          'recipe_id': 1,
          'servings': 4,
          'timer_started_at': '2026-01-01T09:00:00.000Z',
        });
      });
      await expectRejected(() async {
        await harness.db.insert('cooking_sessions', <String, Object?>{
          'kitchen_id': 1,
          'recipe_id': 1,
          'servings': 4,
          'status': 'completed',
          'completed_at': '2026-01-01T10:00:00.000Z',
          'timer_started_at': '2026-01-01T09:00:00.000Z',
          'timer_duration_seconds': 300,
        });
      });
    });

    test('one active session per kitchen (partial unique index)', () async {
      await harness.db.insert('cooking_sessions', <String, Object?>{
        'kitchen_id': 1,
        'recipe_id': 1,
        'servings': 4,
      });
      await expectRejected(() async {
        await harness.db.insert('cooking_sessions', <String, Object?>{
          'kitchen_id': 1,
          'recipe_id': 2,
          'servings': 2,
        });
      });
      // Completing the first frees the slot.
      await harness.db.update('cooking_sessions', <String, Object?>{
        'status': 'completed',
        'completed_at': '2026-01-01T10:00:00.000Z',
      }, where: 'id = 1');
      await harness.db.insert('cooking_sessions', <String, Object?>{
        'kitchen_id': 1,
        'recipe_id': 2,
        'servings': 2,
      });
      expect(await harness.db.query('cooking_sessions'), hasLength(2));
    });

    test(
      'session_step_choices needs a variant id iff it is a variant',
      () async {
        await harness.db.insert('cooking_sessions', <String, Object?>{
          'kitchen_id': 1,
          'recipe_id': 3,
          'servings': 4,
        });
        await expectRejected(() async {
          await harness.db.insert('session_step_choices', <String, Object?>{
            'session_id': 1,
            'step_number': 1,
            'is_variant': 1,
            'variant_id': null,
          });
        });
        await expectRejected(() async {
          await harness.db.insert('session_step_choices', <String, Object?>{
            'session_id': 1,
            'step_number': 2,
            'is_variant': 0,
            'variant_id': 1,
          });
        });
      },
    );

    test('at most one usage event per ingredient per session', () async {
      await harness.db.insert('cooking_sessions', <String, Object?>{
        'kitchen_id': 1,
        'recipe_id': 1,
        'servings': 4,
      });
      await harness.db.insert('stock_event', <String, Object?>{
        'ingredient_id': 1,
        'from_status': 'have',
        'to_status': 'low',
        'reason': 'used_some',
        'cooking_session_id': 1,
      });
      await expectRejected(() async {
        await harness.db.insert('stock_event', <String, Object?>{
          'ingredient_id': 1,
          'from_status': 'low',
          'to_status': 'out',
          'reason': 'used_up',
          'cooking_session_id': 1,
        });
      });
    });
  });

  test('the DDL splitter keeps comments and quoted semicolons intact', () {
    final statements = splitSqlStatements(
      "-- a comment; with a semicolon\n"
      "CREATE TABLE a (x TEXT DEFAULT ';');\n"
      "INSERT INTO a (x) VALUES ('hello');\n",
    );
    expect(statements, hasLength(2));
    expect(statements.first, contains("';'"));
    expect(statements.last, contains('hello'));
  });
}
