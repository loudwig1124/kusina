/// The bundled DDL (`db/schema-sqlite.sql`) and the statement splitter used to
/// apply it (`docs/08` §4.10).
///
/// The file stays the single source of truth: the app applies the same artifact
/// the CLI validates with `sqlite3 :memory: ".read db/schema-sqlite.sql"`.
library;

import 'package:flutter/services.dart';

/// Asset key of the shipped schema (declared in `pubspec.yaml`).
const String schemaAssetKey = 'db/schema-sqlite.sql';

typedef SchemaLoader = Future<String> Function();

/// Loads the schema from the app bundle.
Future<String> loadSchemaAsset() => rootBundle.loadString(schemaAssetKey);

/// Splits a SQL script into executable statements: `;` outside string literals
/// and `--` comments ends a statement. The shipped DDL has no triggers and no
/// `BEGIN`/`COMMIT`, so this mirrors `sqlite3 .read` closely enough to apply it.
List<String> splitSqlStatements(String script) {
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
