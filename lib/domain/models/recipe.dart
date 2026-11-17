/// Recipe content models: one canonical step list plus bounded per-method
/// deltas (`docs/09` §4.1-§4.3, `assets/README.md` §1.4-1.5).
///
/// Pure Dart. Nothing here selects a method for the cook: [RecipeMethod] is
/// declared content, and resolution always needs the method the cook picked.
library;

/// Step kind; drives the sprite family and which fields are required.
enum StepKind {
  prep('prep'),
  heat('heat'),
  cook('cook'),
  wait('wait'),
  finish('finish');

  const StepKind(this.wireCode);

  final String wireCode;

  static StepKind fromWire(String value) {
    for (final kind in StepKind.values) {
      if (kind.wireCode == value) {
        return kind;
      }
    }
    throw ArgumentError.value(value, 'kind', 'unknown step kind');
  }
}

/// One cook-chosen method of a dish: `Pan-fry` (`pan_fry` → stovetop) or
/// `Air-fry` (`air_fry` → air fryer). Declared content, never a default.
class RecipeMethod {
  const RecipeMethod({
    required this.key,
    required this.label,
    required this.equipmentCode,
    required this.iconKey,
    required this.isCanonical,
  });

  /// Stable key (`pan_fry`, `air_fry`).
  final String key;

  /// Locked title-case label (`Pan-fry`, `Air-fry`).
  final String label;

  /// The appliance this method needs, e.g. `air_fryer`.
  final String equipmentCode;

  /// Art key for the method button sprite (`variant_panfry`).
  final String iconKey;

  /// True for the method implemented by the canonical step rows. Never used to
  /// pick a method for the cook — only to resolve the canonical rows.
  final bool isCanonical;
}

/// A method's delta for one step (`recipe_step_variants`). Only instruction,
/// duration, sprite and priority may change; never the step count or order.
class StepVariant {
  const StepVariant({
    required this.methodKey,
    required this.equipmentCode,
    this.instruction,
    this.durationSeconds,
    this.spriteKey,
    required this.priority,
  });

  final String methodKey;
  final String equipmentCode;
  final String? instruction;
  final int? durationSeconds;
  final String? spriteKey;

  /// Authoring column only; path planning never reads it (`docs/09` §4.5).
  final int priority;
}

/// The concrete text/timer/appliance a step has on one path.
class StepImplementation {
  const StepImplementation({
    required this.instruction,
    required this.detail,
    required this.durationSeconds,
    required this.spriteKey,
    required this.equipmentCode,
    required this.isVariant,
    this.variant,
  });

  final String instruction;
  final String? detail;
  final int? durationSeconds;
  final String spriteKey;
  final String? equipmentCode;

  /// True when a [StepVariant] supplied this implementation.
  final bool isVariant;
  final StepVariant? variant;
}

/// One authored step. Invariants checked by `tool/validate_content.py`.
class RecipeStep {
  const RecipeStep({
    required this.stepNumber,
    required this.kind,
    required this.instruction,
    this.detail,
    this.durationSeconds,
    this.equipmentCode,
    required this.ingredientRefs,
    this.caution,
    required this.spriteKey,
    this.variantGroup,
    required this.variants,
  });

  /// Contiguous `1..N`; one `finish` step, always the last.
  final int stepNumber;
  final StepKind kind;
  final String instruction;
  final String? detail;

  /// `> 0` only on `heat`/`cook`/`wait`; `wait` requires it.
  final int? durationSeconds;

  /// Appliance for `heat`/`cook` (required), optional for `wait`, null otherwise.
  final String? equipmentCode;
  final List<String> ingredientRefs;
  final String? caution;
  final String spriteKey;

  /// The share group for method-dependent steps (`cook_method`), else null.
  final String? variantGroup;
  final List<StepVariant> variants;

  /// True when this step differs by method.
  bool get isMethodDependent => variantGroup != null || variants.isNotEmpty;

  StepVariant? variantFor(String methodKey) {
    for (final variant in variants) {
      if (variant.methodKey == methodKey) {
        return variant;
      }
    }
    return null;
  }

  /// Resolves this step for [method] following `assets/README.md` §1.5:
  ///
  /// * no variants — the canonical implementation, for every method;
  /// * a variant for the method — that variant's delta over the canonical row;
  /// * no variant, canonical method and the step's appliance is the method's —
  ///   the canonical implementation (the air-fry path);
  /// * otherwise the method cannot resolve (`null`, a content error).
  ///
  /// A method-dependent step with no method is an error: there is no default.
  StepImplementation? resolveFor(RecipeMethod? method) {
    if (variants.isEmpty) {
      return _canonical();
    }
    if (method == null) {
      throw ArgumentError(
        'Step $stepNumber depends on variant group "$variantGroup"; '
        'the cook must pick a method first',
      );
    }
    final variant = variantFor(method.key);
    if (variant != null) {
      return StepImplementation(
        instruction: variant.instruction ?? instruction,
        detail: detail,
        durationSeconds: variant.durationSeconds ?? durationSeconds,
        spriteKey: variant.spriteKey ?? spriteKey,
        equipmentCode: variant.equipmentCode,
        isVariant: true,
        variant: variant,
      );
    }
    if (method.isCanonical && equipmentCode == method.equipmentCode) {
      return _canonical();
    }
    return null;
  }

  StepImplementation _canonical() => StepImplementation(
    instruction: instruction,
    detail: detail,
    durationSeconds: durationSeconds,
    spriteKey: spriteKey,
    equipmentCode: equipmentCode,
    isVariant: false,
  );
}

/// One display-only ingredient line: quantity and unit are prose, never input
/// (`docs/06` §3.3 A3 / `docs/07` §5.3).
class RecipeLine {
  const RecipeLine({
    required this.ingredientCode,
    required this.name,
    required this.quantity,
    required this.unitCode,
    required this.isOptional,
    this.preparationNote,
  });

  final String ingredientCode;
  final String name;
  final num quantity;
  final String unitCode;
  final bool isOptional;
  final String? preparationNote;

  /// `1000 g` / `6 clove` — read-only label text.
  String get quantityLabel {
    final amount = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toString();
    return '$amount $unitCode';
  }
}

/// A dish as the cook sees it: identity, display metadata, the method choices,
/// the canonical steps and the display ingredient lines.
class RecipeDetail {
  const RecipeDetail({
    required this.slug,
    required this.name,
    required this.description,
    required this.cuisine,
    required this.baseServings,
    required this.prepMinutes,
    required this.cookMinutes,
    required this.difficulty,
    required this.sortOrder,
    required this.dishStampKey,
    required this.requiredEquipmentCodes,
    required this.methods,
    required this.lines,
    required this.steps,
  });

  /// Lower-case slug; the domain id for a recipe.
  final String slug;
  final String name;
  final String description;
  final String cuisine;

  /// Base yield. Static text; there is no serving selector (`docs/06` A6).
  final int baseServings;
  final int prepMinutes;
  final int cookMinutes;
  final String difficulty;
  final int sortOrder;

  /// `dish_chicken_adobo` art key.
  final String dishStampKey;

  /// Method-independent appliances. Empty for a method dish — the method
  /// declares its own appliance (`assets/README.md` §1.5).
  final List<String> requiredEquipmentCodes;

  /// Declared methods, empty for single-path dishes.
  final List<RecipeMethod> methods;
  final List<RecipeLine> lines;
  final List<RecipeStep> steps;

  bool get hasMethodChoice => methods.length > 1;

  List<RecipeLine> get requiredLines =>
      lines.where((line) => !line.isOptional).toList(growable: false);

  List<RecipeLine> get optionalLines =>
      lines.where((line) => line.isOptional).toList(growable: false);

  int get totalMinutes => prepMinutes + cookMinutes;

  String get servingsLabel => 'Base yield: $baseServings servings';

  RecipeMethod? methodFor(String? key) {
    if (key == null) {
      return null;
    }
    for (final method in methods) {
      if (method.key == key) {
        return method;
      }
    }
    return null;
  }

  /// The method implemented by the canonical step rows, or null. Display only:
  /// it never preselects a picker and never starts a path (`docs/09` §4.2).
  RecipeMethod? get canonicalMethod {
    for (final method in methods) {
      if (method.isCanonical) {
        return method;
      }
    }
    return null;
  }

  /// The appliances a path needs: the method-independent ones plus every
  /// appliance the chosen implementations of the steps use.
  ///
  /// Throws when a method dish is asked for without the cook's pick — there is
  /// no default to fall back to.
  Set<String> equipmentCodesFor(String? methodKey) {
    final method = _requireMethod(methodKey);
    final codes = <String>{...requiredEquipmentCodes};
    for (final step in steps) {
      final implementation = step.resolveFor(method);
      final equipmentCode = implementation?.equipmentCode ?? step.equipmentCode;
      if (equipmentCode != null) {
        codes.add(equipmentCode);
      }
    }
    return Set.unmodifiable(codes);
  }

  /// Variant groups whose chosen path cannot be resolved (a content error that
  /// becomes a `group:<key>` missing requirement).
  Set<String> unresolvedGroupsFor(String? methodKey) {
    final method = _requireMethod(methodKey);
    final unresolved = <String>{};
    for (final step in steps) {
      final group = step.variantGroup;
      if (group == null || step.variants.isEmpty) {
        continue;
      }
      if (step.resolveFor(method) == null) {
        unresolved.add(group);
      }
    }
    return Set.unmodifiable(unresolved);
  }

  RecipeMethod? _requireMethod(String? methodKey) {
    if (methods.isEmpty) {
      if (methodKey != null) {
        throw ArgumentError.value(
          methodKey,
          'methodKey',
          '$slug has no methods; pass null',
        );
      }
      return null;
    }
    if (methodKey == null) {
      throw ArgumentError(
        '$slug ships ${methods.length} methods; the cook must pick one '
        '(no auto-selection, docs/09 §4.2)',
      );
    }
    final method = methodFor(methodKey);
    if (method == null) {
      throw ArgumentError.value(methodKey, 'methodKey', 'unknown method');
    }
    return method;
  }
}
