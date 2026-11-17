/// Loads the fixture JSON text for the composition root.
///
/// The app reads the bundled `assets/fixtures/` content; tests read the same
/// files from disk. Both produce the `path -> JSON text` map that
/// `FixtureBundle.parse` consumes, so no second content copy exists.
library;

import 'package:flutter/services.dart';

abstract interface class FixtureSource {
  Future<Map<String, String>> load();
}

/// Reads every JSON file under `assets/fixtures/` from the app bundle.
///
/// `recipes/` is discovered through the asset manifest, so adding a dish is a
/// content change, not a code change.
class AssetFixtureSource implements FixtureSource {
  const AssetFixtureSource();

  static const String _prefix = 'assets/fixtures/';

  @override
  Future<Map<String, String>> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths =
        manifest
            .listAssets()
            .where((path) => path.startsWith(_prefix) && path.endsWith('.json'))
            .toList()
          ..sort();
    final files = <String, String>{};
    for (final path in paths) {
      files[path] = await rootBundle.loadString(path);
    }
    return Map.unmodifiable(files);
  }
}
