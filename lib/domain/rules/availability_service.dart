/// Availability is advisory (`docs/06` §3.1 A1 / `docs/08` §5.3).
///
/// Pure Dart: no I/O, no widgets, no database. One implementation serves the
/// Phase A fixtures and the Phase B SQLite layer, so the rule cannot fork.
library;

import '../models/recipe.dart';
import '../models/stock.dart';

/// The three states a recipe can be in for a given method.
enum AvailabilityState {
  ready('ready'),
  needsConfirmation('needs_confirmation'),
  blocked('blocked');

  const AvailabilityState(this.wireCode);

  final String wireCode;
}

/// What kind of requirement a [MissingRequirement] names.
enum MissingRequirementKind { equipment, ingredient, group }

/// One stable missing-requirement code, typed for rendering and for the
/// session snapshot (`equipment:air_fryer`, `ingredient:bay_leaf`).
class MissingRequirement {
  const MissingRequirement({required this.kind, required this.code});

  final MissingRequirementKind kind;

  /// The equipment code, ingredient code or variant-group key.
  final String code;

  /// The stable code string (`docs/08` §5.1).
  String get stableCode => '${kind.name}:$code';

  @override
  bool operator ==(Object other) =>
      other is MissingRequirement && other.kind == kind && other.code == code;

  @override
  int get hashCode => Object.hash(kind, code);

  @override
  String toString() => stableCode;
}

/// The availability of one recipe for one method (or for a dish with a single
/// path). `blocked` when anything is missing, `needsConfirmation` when nothing
/// is missing but a required ingredient is `unknown`, `ready` otherwise.
class AvailabilityResult {
  const AvailabilityResult({
    required this.state,
    required this.methodKey,
    required this.requiredEquipmentCodes,
    required this.missing,
    required this.unconfirmedIngredientCodes,
    required this.lowIngredientCodes,
  });

  final AvailabilityState state;

  /// The method this result was computed for; null for single-path dishes.
  final String? methodKey;

  /// Every appliance the chosen path needs.
  final Set<String> requiredEquipmentCodes;

  /// Sorted by [MissingRequirement.stableCode].
  final List<MissingRequirement> missing;

  /// Required ingredients whose status is `unknown` — flagged, never blocking.
  final List<String> unconfirmedIngredientCodes;

  /// Required ingredients whose status is `low` — available but warn.
  final List<String> lowIngredientCodes;

  bool get isReady => state == AvailabilityState.ready;
  bool get isBlocked => state == AvailabilityState.blocked;
  bool get needsConfirmation => state == AvailabilityState.needsConfirmation;

  /// Availability never forbids a start: `Guide me anyway` always exists
  /// (`docs/06` §3.1 A1, `docs/09` §4.2).
  bool get guideAnywayAllowed => true;

  /// Stable codes for the session snapshot.
  List<String> get missingCodes => missing
      .map((requirement) => requirement.stableCode)
      .toList(growable: false);

  /// The primary action label for this state (`docs/07` §0 rule 9).
  String get startActionLabel => switch (state) {
    AvailabilityState.ready => 'Start cooking',
    AvailabilityState.needsConfirmation => 'Start and confirm items',
    AvailabilityState.blocked => 'Guide me anyway',
  };
}

/// Batch facade over the presence rule; the only availability entry point
/// outside the guide engine.
abstract interface class AvailabilityService {
  /// Evaluates [recipe] for the method the cook picked.
  ///
  /// For a dish with more than one method, [methodKey] is required: nothing
  /// selects a method on the cook's behalf (`docs/09` §4.2).
  AvailabilityResult evaluate({
    required RecipeDetail recipe,
    required String? methodKey,
    required Set<String> ownedEquipmentCodes,
    required Map<String, StockStatus> statuses,
  });

  /// One display result per recipe for list badges. A method dish reports the
  /// best method's state and names it; this never pins or starts a path
  /// (`docs/08` §5.3).
  Map<String, AvailabilityResult> evaluateAll({
    required Iterable<RecipeDetail> recipes,
    required Set<String> ownedEquipmentCodes,
    required Map<String, StockStatus> statuses,
  });
}

/// The single implementation of the presence rule.
class PresenceAvailabilityService implements AvailabilityService {
  const PresenceAvailabilityService();

  @override
  AvailabilityResult evaluate({
    required RecipeDetail recipe,
    required String? methodKey,
    required Set<String> ownedEquipmentCodes,
    required Map<String, StockStatus> statuses,
  }) {
    final method = _requireMethod(recipe, methodKey);
    return _evaluateFor(recipe, method, ownedEquipmentCodes, statuses);
  }

  @override
  Map<String, AvailabilityResult> evaluateAll({
    required Iterable<RecipeDetail> recipes,
    required Set<String> ownedEquipmentCodes,
    required Map<String, StockStatus> statuses,
  }) {
    final results = <String, AvailabilityResult>{};
    for (final recipe in recipes) {
      results[recipe.slug] = _bestResult(recipe, ownedEquipmentCodes, statuses);
    }
    return Map.unmodifiable(results);
  }

  /// The best method's result for a list badge, in declaration order on a tie.
  /// Display-only: it is never written to a session or used to start a guide.
  AvailabilityResult _bestResult(
    RecipeDetail recipe,
    Set<String> ownedEquipmentCodes,
    Map<String, StockStatus> statuses,
  ) {
    if (!recipe.hasMethodChoice) {
      return _evaluateFor(recipe, null, ownedEquipmentCodes, statuses);
    }
    AvailabilityResult? best;
    for (final method in recipe.methods) {
      final result = _evaluateFor(
        recipe,
        method,
        ownedEquipmentCodes,
        statuses,
      );
      if (best == null || _rank(result.state) < _rank(best.state)) {
        best = result;
      }
    }
    return best!;
  }

  static int _rank(AvailabilityState state) => switch (state) {
    AvailabilityState.ready => 0,
    AvailabilityState.needsConfirmation => 1,
    AvailabilityState.blocked => 2,
  };

  AvailabilityResult _evaluateFor(
    RecipeDetail recipe,
    RecipeMethod? method,
    Set<String> ownedEquipmentCodes,
    Map<String, StockStatus> statuses,
  ) {
    // Equipment: exactly the appliances the chosen path needs. For a method
    // dish that is the union of the shared step appliances and the picked
    // method's appliance; `recipe_equipment` is empty there by design.
    final requiredEquipment = recipe.equipmentCodesFor(method?.key);
    final missingEquipment = <String>[
      for (final code in requiredEquipment)
        if (!ownedEquipmentCodes.contains(code)) code,
    ]..sort();

    final unresolvedGroups = recipe.unresolvedGroupsFor(method?.key).toList()
      ..sort();

    // Ingredients: optional lines are excluded from every set. No row reads as
    // `unknown`; nothing is inferred from absence.
    final missingIngredients = <String>[];
    final unconfirmed = <String>[];
    final low = <String>[];
    for (final line in recipe.requiredLines) {
      final status = statuses[line.ingredientCode] ?? StockStatus.unknown;
      switch (status) {
        case StockStatus.out:
          missingIngredients.add(line.ingredientCode);
        case StockStatus.unknown:
          unconfirmed.add(line.ingredientCode);
        case StockStatus.low:
          low.add(line.ingredientCode);
        case StockStatus.have:
          break;
      }
    }
    missingIngredients.sort();
    unconfirmed.sort();
    low.sort();

    final missing = <MissingRequirement>[
      for (final code in missingEquipment)
        MissingRequirement(kind: MissingRequirementKind.equipment, code: code),
      for (final code in missingIngredients)
        MissingRequirement(kind: MissingRequirementKind.ingredient, code: code),
      for (final code in unresolvedGroups)
        MissingRequirement(kind: MissingRequirementKind.group, code: code),
    ]..sort((a, b) => a.stableCode.compareTo(b.stableCode));

    final state = missing.isNotEmpty
        ? AvailabilityState.blocked
        : unconfirmed.isNotEmpty
        ? AvailabilityState.needsConfirmation
        : AvailabilityState.ready;

    return AvailabilityResult(
      state: state,
      methodKey: method?.key,
      requiredEquipmentCodes: requiredEquipment,
      missing: List.unmodifiable(missing),
      unconfirmedIngredientCodes: List.unmodifiable(unconfirmed),
      lowIngredientCodes: List.unmodifiable(low),
    );
  }

  RecipeMethod? _requireMethod(RecipeDetail recipe, String? methodKey) {
    if (!recipe.hasMethodChoice) {
      if (methodKey != null) {
        throw ArgumentError.value(
          methodKey,
          'methodKey',
          '${recipe.slug} has no method choices',
        );
      }
      return null;
    }
    if (methodKey == null) {
      throw ArgumentError(
        '${recipe.slug} ships ${recipe.methods.length} methods; availability '
        'is always for the method the cook picked (no auto-selection)',
      );
    }
    final method = recipe.methodFor(methodKey);
    if (method == null) {
      throw ArgumentError.value(methodKey, 'methodKey', 'unknown method');
    }
    return method;
  }
}
