/// Layer-rule guard (`docs/08` §3): the domain stays pure Dart and the pixel
/// kit stays presentation-only. A failing import here is an architecture bug,
/// not a style nit.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> dartFilesUnder(String path) {
  final directory = Directory(path);
  expect(directory.existsSync(), isTrue, reason: '$path must exist');
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

List<String> importsOf(File file) => file
    .readAsLinesSync()
    .where((line) => line.trimLeft().startsWith('import '))
    .toList();

void main() {
  test('lib/domain imports no Flutter, sqflite, dart:io or asset APIs', () {
    const forbidden = <String>[
      'package:flutter/',
      'package:sqflite',
      'dart:io',
      'dart:ui',
      'package:path_provider',
      'rootBundle',
    ];
    final files = dartFilesUnder('lib/domain');
    expect(files, isNotEmpty);

    for (final file in files) {
      for (final line in importsOf(file)) {
        for (final banned in forbidden) {
          expect(
            line.contains(banned),
            isFalse,
            reason: '${file.path} must not import $banned',
          );
        }
      }
    }
  });

  test('lib/domain has no Flutter widget usage', () {
    for (final file in dartFilesUnder('lib/domain')) {
      final source = file.readAsStringSync();
      expect(source.contains('Widget'), isFalse, reason: file.path);
      expect(source.contains('BuildContext'), isFalse, reason: file.path);
    }
  });

  test('lib/ui/pixel is presentation-only', () {
    const forbidden = <String>[
      'package:kusina/app/',
      'package:kusina/data/',
      'package:kusina/features/',
      'package:sqflite',
    ];
    for (final file in dartFilesUnder('lib/ui/pixel')) {
      for (final line in importsOf(file)) {
        for (final banned in forbidden) {
          expect(
            line.contains(banned),
            isFalse,
            reason: '${file.path} must not import $banned',
          );
        }
      }
    }
  });

  test('only the composition root and the fixture repositories name fixtures', () {
    // di.dart is the single swap point; nothing else may pick a repository set.
    for (final file in dartFilesUnder('lib')) {
      if (file.path.endsWith('lib/app/di.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      final importsFixture = source.contains('data/repositories/fixture/');
      expect(
        importsFixture,
        isFalse,
        reason:
            '${file.path} imports a concrete fixture repository; only '
            'lib/app/di.dart may (docs/08 §6.3)',
      );
    }
  });

  test('no screen or widget writes SQL', () {
    for (final file in <File>[
      ...dartFilesUnder('lib/features'),
      ...dartFilesUnder('lib/ui'),
    ]) {
      final source = file.readAsStringSync().toUpperCase();
      expect(source.contains('SELECT '), isFalse, reason: file.path);
      expect(source.contains('INSERT INTO'), isFalse, reason: file.path);
      expect(source.contains('UPDATE '), isFalse, reason: file.path);
    }
  });
}
