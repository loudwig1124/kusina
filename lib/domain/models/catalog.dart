/// Catalog models: the 15 ingredients and 5 appliances (`assets/fixtures`).
///
/// Pure Dart (docs/08 §3 layer rule 1). Codes are the stable identities used by
/// every other layer; integer row ids never leave the data layer.
library;

import 'stock.dart';

/// One catalog ingredient. Stock is presence-only, so no quantity lives here.
class Ingredient {
  const Ingredient({
    required this.code,
    required this.name,
    required this.filipinoGloss,
    required this.category,
    required this.displayUnit,
    required this.defaultStatus,
    required this.spriteKey,
  });

  /// Stable snake_case code, e.g. `bay_leaf`.
  final String code;

  /// English label, e.g. `Bay leaf`.
  final String name;

  /// Filipino gloss, e.g. `Laurel`.
  final String filipinoGloss;

  /// One of `produce | meat | seafood | dairy_eggs | pantry | condiments | spices`.
  final String category;

  /// Display vocabulary only (`g`, `ml`, `pc`, `clove`); never converted.
  final String displayUnit;

  /// Status a fresh kitchen gets: `unknown` for every catalog ingredient.
  final StockStatus defaultStatus;

  /// `ing_<code>` art key.
  final String spriteKey;

  /// `Garlic (Bawang)` — the label the inventory row and detail use.
  String get label => '$name ($filipinoGloss)';
}

/// One appliance. `shipped` marks appliances used by a shipped dish; the rest
/// still appear in the picker with [pickerNote].
class Equipment {
  const Equipment({
    required this.code,
    required this.name,
    required this.description,
    required this.shipped,
    this.pickerNote,
    required this.spriteKey,
  });

  /// Stable code, e.g. `air_fryer`.
  final String code;
  final String name;
  final String description;

  /// True when a shipped dish needs it (`stovetop`, `air_fryer`).
  final bool shipped;

  /// Non-null for unused appliances, e.g. `No dishes yet`.
  final String? pickerNote;

  /// `eq_<code>` art key.
  final String spriteKey;
}
