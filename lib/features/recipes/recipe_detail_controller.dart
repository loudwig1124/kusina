/// Recipe-detail view state: the cook's method pick and the availability that
/// follows it (`docs/07` §7.1).
///
/// A pure snapshot rebuilt from the latest environment on every frame: it never
/// picks a method, never falls back to the other method, and carries no I/O.
library;

import '../../domain/models/recipe.dart';
import '../../domain/models/stock.dart';
import '../../domain/rules/availability_service.dart';

class RecipeDetailController {
  RecipeDetailController({
    required this.recipe,
    required this.availabilityService,
    required Set<String> ownedEquipmentCodes,
    required Map<String, StockStatus> statuses,
    String? selectedMethodKey,
  }) : _ownedEquipmentCodes = Set<String>.of(ownedEquipmentCodes),
       _statuses = Map<String, StockStatus>.of(statuses),
       _selectedMethodKey = selectedMethodKey {
    if (selectedMethodKey != null &&
        recipe.methodFor(selectedMethodKey) == null) {
      throw ArgumentError.value(
        selectedMethodKey,
        'selectedMethodKey',
        'unknown method',
      );
    }
    for (final method in recipe.methods) {
      _methodAvailability[method.key] = _evaluate(method.key);
    }
  }

  final RecipeDetail recipe;
  final AvailabilityService availabilityService;

  final Set<String> _ownedEquipmentCodes;
  final Map<String, StockStatus> _statuses;
  final String? _selectedMethodKey;
  final Map<String, AvailabilityResult> _methodAvailability =
      <String, AvailabilityResult>{};

  /// Null until the cook taps a method — this is the no-default rule.
  String? get selectedMethodKey => _selectedMethodKey;

  /// Availability of every method, for the per-method badges.
  Map<String, AvailabilityResult> get methodAvailability =>
      Map.unmodifiable(_methodAvailability);

  AvailabilityResult? availabilityFor(String methodKey) {
    if (!recipe.hasMethodChoice) {
      return _evaluate(null);
    }
    return _methodAvailability[methodKey] ?? _evaluate(methodKey);
  }

  /// Availability of the picked method, or null while nothing is picked.
  AvailabilityResult? get selectedAvailability {
    if (!recipe.hasMethodChoice) {
      return _evaluate(null);
    }
    final key = _selectedMethodKey;
    if (key == null) {
      return null;
    }
    return _methodAvailability[key] ?? _evaluate(key);
  }

  bool get needsMethodChoice =>
      recipe.hasMethodChoice && _selectedMethodKey == null;

  bool get canStart => !needsMethodChoice;

  /// Primary action copy: the method prompt while nothing is picked, otherwise
  /// the availability-driven label (Start cooking / Start and confirm items /
  /// Guide me anyway).
  String get primaryLabel {
    if (needsMethodChoice) {
      return 'Choose $_methodLabels';
    }
    return selectedAvailability?.startActionLabel ?? 'Start cooking';
  }

  String get _methodLabels {
    final labels = recipe.methods.map((method) => method.label).toList();
    if (labels.length <= 1) {
      return labels.join();
    }
    return '${labels.sublist(0, labels.length - 1).join(', ')} or ${labels.last}';
  }

  AvailabilityResult _evaluate(String? methodKey) =>
      availabilityService.evaluate(
        recipe: recipe,
        methodKey: methodKey,
        ownedEquipmentCodes: _ownedEquipmentCodes,
        statuses: _statuses,
      );
}
