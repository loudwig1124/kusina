/// Equipment repository on SQLite (`docs/08` §5.2).
///
/// `shipped` is derived: an appliance a shipped dish references (recipe
/// equipment, step equipment or a variant) is in use; the rest keep the
/// "No dishes yet" note. Ownership is the one editable set (kitchen_equipment).
library;

import 'package:sqflite/sqflite.dart';

import '../../domain/models/catalog.dart';
import '../repositories/equipment_repository.dart';
import 'app_database.dart';

class SqliteEquipmentRepository implements EquipmentRepository {
  const SqliteEquipmentRepository(this._db, {this.clock});

  final Database _db;
  final DateTime Function()? clock;

  static const int _kitchenId = 1;

  DateTime _now() => (clock ?? () => DateTime.now().toUtc())();

  @override
  Future<List<Equipment>> catalog() async {
    final rows = await _db.rawQuery(
      'SELECT e.id AS id, e.code AS code, e.name AS name, '
      '  e.description AS description, '
      '  (EXISTS (SELECT 1 FROM recipe_equipment re WHERE re.equipment_id = e.id) '
      '   OR EXISTS (SELECT 1 FROM recipe_steps s WHERE s.equipment_id = e.id) '
      '   OR EXISTS (SELECT 1 FROM recipe_step_variants v '
      '              WHERE v.equipment_id = e.id)) AS shipped '
      'FROM equipment e ORDER BY e.id',
    );
    return List<Equipment>.unmodifiable(<Equipment>[
      for (final row in rows)
        Equipment(
          code: row['code']! as String,
          name: row['name']! as String,
          description: (row['description'] as String?) ?? '',
          shipped: (row['shipped']! as int) == 1,
          pickerNote: (row['shipped']! as int) == 1 ? null : 'No dishes yet',
          spriteKey: 'eq_${row['code']! as String}',
        ),
    ]);
  }

  @override
  Future<Set<String>> ownedIds() async {
    final rows = await _db.rawQuery(
      'SELECT e.code AS code FROM kitchen_equipment ke '
      'JOIN equipment e ON e.id = ke.equipment_id '
      'WHERE ke.kitchen_id = ? ORDER BY e.id',
      <Object?>[_kitchenId],
    );
    return Set<String>.unmodifiable(rows.map((row) => row['code']! as String));
  }

  @override
  Future<void> setOwned(Set<String> equipmentCodes) async {
    await _db.transaction((txn) async {
      final known = <String>{
        for (final row in await txn.query(
          'equipment',
          columns: <String>['code'],
        ))
          row['code']! as String,
      };
      final unknown = equipmentCodes.difference(known);
      if (unknown.isNotEmpty) {
        throw ArgumentError('unknown appliance codes: ${unknown.join(', ')}');
      }
      await txn.delete(
        'kitchen_equipment',
        where: 'kitchen_id = ?',
        whereArgs: <Object?>[_kitchenId],
      );
      final now = isoUtc(_now());
      for (final code in equipmentCodes.toList()..sort()) {
        await txn.rawInsert(
          'INSERT INTO kitchen_equipment (kitchen_id, equipment_id, created_at) '
          'VALUES (?, (SELECT id FROM equipment WHERE code = ?), ?)',
          <Object?>[_kitchenId, code, now],
        );
      }
    });
  }
}
