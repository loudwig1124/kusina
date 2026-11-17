/// Kitchen profile repository on SQLite (`docs/08` §5.2): the single row.
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/models/kitchen.dart';
import '../repositories/kitchen_repository.dart';
import 'app_database.dart';

class SqliteKitchenRepository implements KitchenRepository {
  const SqliteKitchenRepository(this._db, {this.clock});

  final Database _db;
  final DateTime Function()? clock;

  static const int _kitchenId = 1;

  DateTime _now() => (clock ?? () => DateTime.now().toUtc())();

  @override
  Future<Kitchen> get() async {
    final rows = await _db.query(
      'kitchens',
      where: 'id = ?',
      whereArgs: <Object?>[_kitchenId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('seed missing: no kitchen row');
    }
    final row = rows.single;
    return Kitchen(
      uid: row['kitchen_uid']! as String,
      name: row['name']! as String,
      createdAt: parseUtc(row['created_at']! as String),
      updatedAt: parseUtc(row['updated_at']! as String),
    );
  }

  @override
  Future<Kitchen> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'kitchen name must not be empty');
    }
    final changed = await _db.update(
      'kitchens',
      <String, Object?>{'name': trimmed, 'updated_at': isoUtc(_now())},
      where: 'id = ?',
      whereArgs: <Object?>[_kitchenId],
    );
    if (changed != 1) {
      throw StateError('seed missing: the kitchen row vanished');
    }
    return get();
  }
}
