/// Phase A recipe repository: the parsed fixture bundle, already ordered.
library;

import '../../../domain/models/recipe.dart';
import '../recipe_repository.dart';
import 'fixture_bundle.dart';

class FixtureRecipeRepository implements RecipeRepository {
  const FixtureRecipeRepository(this._bundle);

  final FixtureBundle _bundle;

  @override
  Future<List<RecipeDetail>> listRecipes() async => _bundle.recipes;

  @override
  Future<RecipeDetail?> findBySlug(String slug) async =>
      _bundle.recipeFor(slug);
}
