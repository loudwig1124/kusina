/// Structural guard: SQL stays in the data layer (`docs/08` §3 layer rule 3).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no SQL text exists outside lib/data', () {
    const markers = <String>[
      'SELECT ',
      'INSERT INTO',
      'DELETE FROM',
      'CREATE TABLE',
      'PRAGMA ',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.path.startsWith('lib/data/')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final marker in markers) {
        if (source.contains(marker)) {
          offenders.add('${entity.path} contains "$marker"');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('only lib/data/sqlite imports sqflite', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      final importsSqflite = source.contains('package:sqflite/');
      if (!importsSqflite) {
        continue;
      }
      final allowed =
          entity.path.startsWith('lib/data/sqlite/') ||
          entity.path == 'lib/app/di.dart';
      if (!allowed) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
