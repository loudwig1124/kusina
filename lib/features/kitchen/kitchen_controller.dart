/// Kitchen profile + equipment selection (`docs/07` §7 screens 1, 10, M1).
library;

import 'package:flutter/foundation.dart';

import '../../data/repositories/equipment_repository.dart';
import '../../data/repositories/kitchen_repository.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/kitchen.dart';

class KitchenController extends ChangeNotifier {
  KitchenController({
    required this.kitchenRepository,
    required this.equipmentRepository,
    this.onResetDemoData,
  });

  final KitchenRepository kitchenRepository;
  final EquipmentRepository equipmentRepository;
  final Future<void> Function()? onResetDemoData;

  bool _loading = true;
  Object? _error;
  Kitchen? _kitchen;
  List<Equipment> _catalog = const <Equipment>[];
  Set<String> _owned = const <String>{};

  bool get isLoading => _loading;
  Object? get error => _error;
  Kitchen? get kitchen => _kitchen;
  List<Equipment> get catalog => _catalog;
  Set<String> get ownedEquipmentCodes => _owned;
  String get kitchenName => _kitchen?.name ?? 'My Kitchen';

  bool owns(String equipmentCode) => _owned.contains(equipmentCode);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _kitchen = await kitchenRepository.get();
      _catalog = await equipmentRepository.catalog();
      _owned = await equipmentRepository.ownedIds();
      _loading = false;
    } catch (error) {
      _error = error;
      _loading = false;
    }
    notifyListeners();
  }

  Future<void> rename(String name) async {
    _kitchen = await kitchenRepository.rename(name);
    notifyListeners();
  }

  Future<void> setEquipmentOwned(String code, {required bool owned}) async {
    final next = <String>{..._owned};
    if (owned) {
      next.add(code);
    } else {
      next.remove(code);
    }
    await equipmentRepository.setOwned(next);
    _owned = next;
    notifyListeners();
  }

  Future<void> resetDemoData() async {
    await onResetDemoData?.call();
    await load();
  }
}
