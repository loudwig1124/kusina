/// Seed/version/reset contract (`docs/08` §5.2).
///
/// Phase A has no database: the fixture implementation reports the content
/// seed version and resets the in-memory demo data. Phase B's SQLite loader
/// implements the same four calls.
library;

abstract interface class SeedLoader {
  Future<void> seedIfNeeded();

  /// Database schema version; 0 when there is no database (Phase A).
  Future<int> schemaVersion();

  /// Content seed version from the fixture JSON.
  Future<int> seedVersion();

  /// Restores the demo kitchen, stock statuses and equipment selection.
  Future<void> resetDemoData();
}
