/// Loads the recipe list plus the environment (equipment, stock) that
/// availability depends on, and hands the screens read-only snapshots.
library;

import 'package:flutter/foundation.dart';

import '../../data/repositories/equipment_repository.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/recipe.dart';
import '../../domain/models/stock.dart';
import '../../domain/rules/availability_service.dart';

/// One recipe plus the display availability for its default method.
class RecipeCardData {
  const RecipeCardData({required this.recipe, required this.availability});

  final RecipeDetail recipe;
  final AvailabilityResult availability;
}

class RecipesController extends ChangeNotifier {
  RecipesController({
    required this.recipeRepository,
    required this.stockRepository,
    required this.equipmentRepository,
    required this.availabilityService,
  });

  final RecipeRepository recipeRepository;
  final StockRepository stockRepository;
  final EquipmentRepository equipmentRepository;
  final AvailabilityService availabilityService;

  bool _loading = true;
  Object? _error;
  List<RecipeDetail> _recipes = const <RecipeDetail>[];
  List<Ingredient> _ingredients = const <Ingredient>[];
  List<Equipment> _equipment = const <Equipment>[];
  Map<String, StockStatus> _statuses = const <String, StockStatus>{};
  Set<String> _owned = const <String>{};
  Map<String, AvailabilityResult> _availability =
      const <String, AvailabilityResult>{};

  bool get isLoading => _loading;
  Object? get error => _error;
  List<RecipeDetail> get recipes => _recipes;
  List<Ingredient> get ingredients => _ingredients;
  List<Equipment> get equipmentCatalog => _equipment;
  Map<String, StockStatus> get statuses => _statuses;
  Set<String> get ownedEquipmentCodes => _owned;

  /// Three cards on the demo kitchen, each badged for the recipe's default
  /// method (best method for a method dish; display only, never a pick).
  List<RecipeCardData> get cards => <RecipeCardData>[
    for (final recipe in _recipes)
      RecipeCardData(
        recipe: recipe,
        availability:
            _availability[recipe.slug] ??
            availabilityService.evaluateAll(
              recipes: <RecipeDetail>[recipe],
              ownedEquipmentCodes: _owned,
              statuses: _statuses,
            )[recipe.slug]!,
      ),
  ];

  RecipeDetail? recipeFor(String slug) {
    for (final recipe in _recipes) {
      if (recipe.slug == slug) {
        return recipe;
      }
    }
    return null;
  }

  Ingredient? ingredientFor(String code) {
    for (final ingredient in _ingredients) {
      if (ingredient.code == code) {
        return ingredient;
      }
    }
    return null;
  }

  Equipment? equipmentFor(String code) {
    for (final item in _equipment) {
      if (item.code == code) {
        return item;
      }
    }
    return null;
  }

  String ingredientName(String code) => ingredientFor(code)?.name ?? code;

  String equipmentName(String code) => equipmentFor(code)?.name ?? code;

  /// Per-method availability for one recipe, for the detail screen's method
  /// badges. Throws when a method dish is asked for without a method.
  AvailabilityResult availabilityFor(String slug, String? methodKey) {
    final recipe = recipeFor(slug);
    if (recipe == null) {
      throw ArgumentError.value(slug, 'slug', 'unknown recipe');
    }
    return availabilityService.evaluate(
      recipe: recipe,
      methodKey: methodKey,
      ownedEquipmentCodes: _owned,
      statuses: _statuses,
    );
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final recipes = await recipeRepository.listRecipes();
      _ingredients = await stockRepository.listIngredients();
      _equipment = await equipmentRepository.catalog();
      _statuses = await stockRepository.getStatuses(
        _ingredients.map((ingredient) => ingredient.code),
      );
      _owned = await equipmentRepository.ownedIds();
      _recipes = recipes;
      _recompute();
      _loading = false;
    } catch (error) {
      _error = error;
      _loading = false;
    }
    notifyListeners();
  }

  /// Re-reads the environment after a stock or equipment change and recomputes
  /// the badges. Cheap: three repositories, ten ingredients.
  Future<void> refresh() async {
    _statuses = await stockRepository.getStatuses(
      _ingredients.map((ingredient) => ingredient.code),
    );
    _owned = await equipmentRepository.ownedIds();
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    _availability = availabilityService.evaluateAll(
      recipes: _recipes,
      ownedEquipmentCodes: _owned,
      statuses: _statuses,
    );
  }
}
