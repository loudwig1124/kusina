/// Phase A equipment repository: the catalog plus the owned set, in memory.
library;

import '../../../domain/models/catalog.dart';
import '../equipment_repository.dart';
import 'fixture_data.dart';

class FixtureEquipmentRepository implements EquipmentRepository {
  const FixtureEquipmentRepository(this._data);

  final FixtureData _data;

  @override
  Future<List<Equipment>> catalog() async => _data.bundle.equipment;

  @override
  Future<Set<String>> ownedIds() async =>
      Set.unmodifiable(_data.ownedEquipmentCodes);

  @override
  Future<void> setOwned(Set<String> equipmentCodes) async {
    final known = _data.bundle.equipment.map((item) => item.code).toSet();
    final unknown = equipmentCodes.difference(known);
    if (unknown.isNotEmpty) {
      throw ArgumentError('unknown appliance codes: ${unknown.join(', ')}');
    }
    _data.ownedEquipmentCodes
      ..clear()
      ..addAll(equipmentCodes);
  }
}
