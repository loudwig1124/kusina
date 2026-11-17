/// Phase A kitchen profile repository: one in-memory kitchen.
library;

import '../../../domain/models/kitchen.dart';
import '../kitchen_repository.dart';
import 'fixture_data.dart';

class FixtureKitchenRepository implements KitchenRepository {
  const FixtureKitchenRepository(this._data);

  final FixtureData _data;

  @override
  Future<Kitchen> get() async => _data.kitchen;

  @override
  Future<Kitchen> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'kitchen name must not be empty');
    }
    _data.kitchen = _data.kitchen.copyWith(name: trimmed);
    return _data.kitchen;
  }
}
