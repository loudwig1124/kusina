/// The one route table (`docs/08` §2.4): ten screens over a four-tab shell,
/// with the setup redirect and the equipment picker kept as a modal.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/guide/guide_screen.dart';
import '../features/guide/usage_review_screen.dart';
import '../features/history/history_screen.dart';
import '../features/kitchen/first_run_screen.dart';
import '../features/recipes/all_recipes_screen.dart';
import '../features/recipes/cook_now_screen.dart';
import '../features/recipes/recipe_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stock/ingredient_detail_screen.dart';
import '../features/stock/inventory_screen.dart';
import '../ui/pixel/pixel_app_bar.dart';
import '../ui/pixel/pixel_canvas.dart';
import '../ui/pixel/pixel_scaffold.dart';
import 'app_scope.dart';
import 'di.dart';

/// Route paths in one place so no screen hard-codes a string.
abstract final class Routes {
  static const String setup = '/setup';
  static const String cookNow = '/';
  static const String recipes = '/recipes';
  static const String recipePattern = '/recipes/:slug';
  static const String guidePattern = '/guide/:sessionId';
  static const String reviewPattern = '/guide/:sessionId/review';
  static const String stock = '/stock';
  static const String ingredientPattern = '/stock/:code';
  static const String history = '/history';
  static const String settings = '/settings';

  static String recipe(String slug) => '/recipes/$slug';
  static String ingredient(String code) => '/stock/$code';

  static String guide({
    required String sessionId,
    String? slug,
    String? methodKey,
    List<String> missingCodes = const <String>[],
  }) {
    final query = <String, String>{
      'slug': ?slug,
      'method': ?methodKey,
      if (missingCodes.isNotEmpty) 'missing': missingCodes.join(','),
    };
    return Uri(
      path: '/guide/$sessionId',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static String review(String sessionId) => '/guide/$sessionId/review';
}

/// Builds the route table. The guide controller lives in `AppScope` (built by
/// `KusinaApp`), so a cook survives navigating away from the guide and back and
/// the Settings guard sees the same session.
GoRouter buildRouter({
  required Repositories repositories,
  String initialLocation = Routes.cookNow,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      if (!repositories.kitchenConfigured &&
          state.matchedLocation != Routes.setup) {
        return Routes.setup;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.setup,
        builder: (context, state) => const FirstRunScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _TabShell(
          currentIndex: _tabIndexFor(state.matchedLocation),
          child: child,
        ),
        routes: <RouteBase>[
          GoRoute(
            path: Routes.cookNow,
            builder: (context, state) => const CookNowScreen(),
          ),
          GoRoute(
            path: Routes.recipes,
            builder: (context, state) => const AllRecipesScreen(),
          ),
          GoRoute(
            path: Routes.stock,
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: Routes.history,
            builder: (context, state) => const HistoryScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.recipePattern,
        builder: (context, state) =>
            RecipeDetailScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: Routes.guidePattern,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          final missing = (query['missing'] ?? '')
              .split(',')
              .where((code) => code.isNotEmpty)
              .toList(growable: false);
          return GuideScreen(
            sessionId: state.pathParameters['sessionId']!,
            recipeSlug: query['slug'],
            methodKey: query['method'],
            guideAnyway: missing.isNotEmpty,
          );
        },
      ),
      GoRoute(
        path: Routes.reviewPattern,
        builder: (context, state) =>
            UsageReviewScreen(sessionId: state.pathParameters['sessionId']!),
      ),
      GoRoute(
        path: Routes.ingredientPattern,
        builder: (context, state) => IngredientDetailScreen(
          ingredientCode: state.pathParameters['code']!,
        ),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => SettingsScreen(
          hasActiveSession: AppScope.of(context).guide.hasActiveSession,
        ),
      ),
    ],
  );
}

int _tabIndexFor(String location) {
  if (location.startsWith(Routes.recipes)) {
    return 1;
  }
  if (location.startsWith(Routes.stock)) {
    return 2;
  }
  if (location.startsWith(Routes.history)) {
    return 3;
  }
  return 0;
}

/// The tab shell: root screens get the four-tab bar, pushed screens do not.
class _TabShell extends StatelessWidget {
  const _TabShell({required this.currentIndex, required this.child});

  final int currentIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = PixelScale.of(context);
    return PixelScreenScaffold(
      bottomNavigationBar: PixelScaleProvider(
        scale: scale,
        child: PixelTabBar(
          currentIndex: currentIndex,
          onTap: (index) => context.go(PixelTab.values[index].route),
        ),
      ),
      child: child,
    );
  }
}
