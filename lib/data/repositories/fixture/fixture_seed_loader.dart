/// Phase A [SeedLoader]: there is no database, so seeding is a no-op and reset
/// restores the parsed fixture snapshot.
library;

import '../../seed/seed_loader.dart';
import 'fixture_data.dart';

class FixtureSeedLoader implements SeedLoader {
  const FixtureSeedLoader(this._data);

  final FixtureData _data;

  @override
  Future<void> seedIfNeeded() async {
    // Fixtures are read at startup; there is nothing to insert.
  }

  @override
  Future<int> schemaVersion() async => 0;

  @override
  Future<int> seedVersion() async => _data.bundle.seedVersion;

  @override
  Future<void> resetDemoData() async => _data.reset();
}
