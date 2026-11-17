// Bootstrap smoke test for the Kusina Flutter toolchain.
//
// Purpose: prove that the workspace-local Flutter SDK can compile and run the
// test harness, that widget tests work, and that the SQLite FFI test database
// (used by every `test/data` suite from Phase B on) opens and executes SQL.
// It deliberately does not import `lib/` so it stays green while the app shell
// is rewritten in Phase A.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('flutter test harness', () {
    test('dart code executes', () {
      expect(2 + 2, 4);
    });

    testWidgets('a Material app builds and renders', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Kusina'))),
        ),
      );

      expect(find.text('Kusina'), findsOneWidget);
    });
  });

  group('sqflite_common_ffi', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('opens an in-memory database and round-trips a row', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await db.execute(
        'CREATE TABLE probe (id INTEGER PRIMARY KEY, label TEXT NOT NULL)',
      );
      await db.insert('probe', {'id': 1, 'label': 'adobo'});

      final rows = await db.query('probe', where: 'id = ?', whereArgs: [1]);
      expect(rows, hasLength(1));
      expect(rows.single['label'], 'adobo');
    });

    test('the shipped db/schema-sqlite.sql DDL loads into SQLite', () async {
      final ddlFile = File('db/schema-sqlite.sql');
      expect(
        ddlFile.existsSync(),
        isTrue,
        reason:
            'db/schema-sqlite.sql is the single source of truth and a '
            'bundled asset; run the tests from the project root.',
      );

      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      // Apply every statement the way `sqlite3 .read db/schema-sqlite.sql` does
      // (the DDL has no triggers or BEGIN/COMMIT blocks), proving the shipped
      // artifact itself parses and applies.
      for (final statement in _splitStatements(ddlFile.readAsStringSync())) {
        await db.execute(statement);
      }

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      final names = tables.map((row) => row['name'] as String).toSet();

      expect(
        names,
        containsAll(<String>[
          'cooking_sessions',
          'equipment',
          'ingredients',
          'kitchens',
          'recipe_equipment',
          'recipe_ingredients',
          'recipe_step_variants',
          'recipe_steps',
          'recipes',
          'session_step_choices',
          'stock_event',
          'stock_status',
        ]),
      );
    });
  });
}

/// Splits a SQL script into individual statements the way `sqlite3 .read` does:
/// `;` outside string literals and comments ends a statement. `db/schema-sqlite.sql`
/// uses `--` comments (a few contain semicolons) and quoted defaults, so a naive
/// `split(';')` would corrupt it.
List<String> _splitStatements(String script) {
  final statements = <String>[];
  final buffer = StringBuffer();
  String? quote;

  for (var i = 0; i < script.length; i++) {
    final char = script[i];

    if (quote != null) {
      buffer.write(char);
      if (char == quote) {
        quote = null;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      quote = char;
      buffer.write(char);
      continue;
    }

    if (char == '-' && i + 1 < script.length && script[i + 1] == '-') {
      while (i < script.length && script[i] != '\n') {
        i++;
      }
      buffer.write('\n');
      continue;
    }

    if (char == ';') {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) {
        statements.add(statement);
      }
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }

  final trailing = buffer.toString().trim();
  if (trailing.isNotEmpty) {
    statements.add(trailing);
  }
  return statements;
}
