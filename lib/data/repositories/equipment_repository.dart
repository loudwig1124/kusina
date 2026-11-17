/// Equipment contract (`docs/08` §5.2). The picker owns the 5-appliance set;
/// availability never hides a dish because an appliance is missing.
library;

import '../../domain/models/catalog.dart';

abstract interface class EquipmentRepository {
  /// The 5 catalog appliances, in fixture order.
  Future<List<Equipment>> catalog();

  /// Codes the kitchen owns (`stovetop`, `air_fryer` in the demo kitchen).
  Future<Set<String>> ownedIds();

  /// Replaces the owned set; unknown codes are rejected.
  Future<void> setOwned(Set<String> equipmentCodes);
}
