/// Copy for the availability panel and the blocked-start confirm sheet.
///
/// One place for the sentences so the panel, the badges and the confirm sheet
/// never drift, and so the missing list always names every missing requirement
/// (`docs/07` §7 rule 4).
library;

import '../../domain/rules/availability_service.dart';

class AvailabilityCopy {
  const AvailabilityCopy._();

  /// One line per missing requirement, in stable-code order.
  static List<String> missingLines(
    AvailabilityResult result, {
    required String Function(String code) equipmentName,
    required String Function(String code) ingredientName,
  }) {
    return <String>[
      for (final requirement in result.missing)
        switch (requirement.kind) {
          MissingRequirementKind.equipment =>
            '${equipmentName(requirement.code)} is missing.',
          MissingRequirementKind.ingredient =>
            '${ingredientName(requirement.code)} is out of stock.',
          MissingRequirementKind.group =>
            'That cooking method is not available for this dish.',
        },
    ];
  }

  /// "1 MISSING ITEM" / "2 MISSING ITEMS".
  static String missingCountLabel(AvailabilityResult result) {
    final count = result.missing.length;
    return count == 1 ? '1 MISSING ITEM' : '$count MISSING ITEMS';
  }

  /// Panel headline for the picked method.
  static String headline(AvailabilityResult result) {
    return switch (result.state) {
      AvailabilityState.ready => 'Everything you need is on hand.',
      AvailabilityState.needsConfirmation =>
        'Confirm the items below before you start.',
      AvailabilityState.blocked =>
        result.missing.length == 1
            ? 'One requirement is missing.'
            : '${result.missing.length} requirements are missing.',
    };
  }

  /// "Confirm: Salt, Calamansi." — the unknown-but-not-blocking prompt.
  static String? confirmLine(
    AvailabilityResult result, {
    required String Function(String code) ingredientName,
  }) {
    if (result.unconfirmedIngredientCodes.isEmpty) {
      return null;
    }
    final names = result.unconfirmedIngredientCodes.map(ingredientName);
    return 'Probably have — confirm: ${names.join(', ')}.';
  }

  /// "You may run short: Spring onion."
  static String? lowLine(
    AvailabilityResult result, {
    required String Function(String code) ingredientName,
  }) {
    if (result.lowIngredientCodes.isEmpty) {
      return null;
    }
    final names = result.lowIngredientCodes.map(ingredientName);
    return 'You may run short: ${names.join(', ')}.';
  }
}
