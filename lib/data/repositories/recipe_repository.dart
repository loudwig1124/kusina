/// Recipe read contract (`docs/08` §5.2). Pure Dart; implementations live in
/// `fixture/` (Phase A) and `sqlite/` (Phase B), and only `lib/app/di.dart`
/// names one.
library;

import '../../domain/models/recipe.dart';

abstract interface class RecipeRepository {
  /// Every shipped dish, ordered by `sortOrder`.
  Future<List<RecipeDetail>> listRecipes();

  /// One dish by slug, or null when it is not seeded.
  Future<RecipeDetail?> findBySlug(String slug);
}
