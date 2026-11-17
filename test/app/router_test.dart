import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/app/router.dart';
import 'package:kusina/features/guide/guide_screen.dart';
import 'package:kusina/features/guide/usage_review_screen.dart';
import 'package:kusina/features/history/history_screen.dart';
import 'package:kusina/features/kitchen/first_run_screen.dart';
import 'package:kusina/features/recipes/all_recipes_screen.dart';
import 'package:kusina/features/recipes/cook_now_screen.dart';
import 'package:kusina/features/recipes/recipe_detail_screen.dart';
import 'package:kusina/features/settings/settings_screen.dart';
import 'package:kusina/features/stock/ingredient_detail_screen.dart';
import 'package:kusina/features/stock/inventory_screen.dart';
import 'package:kusina/ui/pixel/pixel_app_bar.dart';
import 'package:kusina/ui/pixel/pixel_button.dart';

import '../helpers/fixture_harness.dart';

void main() {
  test('the route table covers the ten locked screens', () {
    expect(Routes.setup, '/setup');
    expect(Routes.cookNow, '/');
    expect(Routes.recipes, '/recipes');
    expect(Routes.recipePattern, '/recipes/:slug');
    expect(Routes.guidePattern, '/guide/:sessionId');
    expect(Routes.reviewPattern, '/guide/:sessionId/review');
    expect(Routes.stock, '/stock');
    expect(Routes.ingredientPattern, '/stock/:code');
    expect(Routes.history, '/history');
    expect(Routes.settings, '/settings');
    expect(PixelTab.values.map((tab) => tab.route).toList(), <String>[
      '/',
      '/recipes',
      '/stock',
      '/history',
    ]);
  });

  testWidgets('the equipment picker is a modal, not an eleventh route', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    await tester.tap(find.widgetWithText(PixelButton, 'EDIT EQUIPMENT'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Unused appliances still appear here.'),
      findsOneWidget,
    );
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(PixelButton, 'DONE'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  group('every route renders', () {
    Future<void> pumpRoute(WidgetTester tester, String location) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: location,
        height: 2400,
      );
    }

    testWidgets('/setup', (tester) async {
      await pumpRoute(tester, '/setup');
      expect(find.byType(FirstRunScreen), findsOneWidget);
      expect(find.text('WELCOME'), findsOneWidget);
      expect(find.text('Start cooking'.toUpperCase()), findsOneWidget);
    });

    testWidgets('/', (tester) async {
      await pumpRoute(tester, '/');
      expect(find.byType(CookNowScreen), findsOneWidget);
    });

    testWidgets('/recipes', (tester) async {
      await pumpRoute(tester, '/recipes');
      expect(find.byType(AllRecipesScreen), findsOneWidget);
    });

    testWidgets('/recipes/chicken-adobo', (tester) async {
      await pumpRoute(tester, '/recipes/chicken-adobo');
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      expect(find.text('Chicken Adobo'), findsOneWidget);
    });

    testWidgets('/guide/:sessionId', (tester) async {
      await pumpRoute(
        tester,
        '/guide/preview?slug=crispy-pork-belly&method=air_fry',
      );
      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.text('STEP 1 OF 6'), findsOneWidget);
      expect(find.text('Air-fry method'), findsOneWidget);
    });

    testWidgets('/guide/:sessionId/review', (tester) async {
      await pumpRoute(tester, '/guide/preview/review');
      expect(find.byType(UsageReviewScreen), findsOneWidget);
      expect(find.text('What did you use?'), findsOneWidget);
    });

    testWidgets('/stock', (tester) async {
      await pumpRoute(tester, '/stock');
      expect(find.byType(InventoryScreen), findsOneWidget);
    });

    testWidgets('/stock/:code', (tester) async {
      await pumpRoute(tester, '/stock/bay_leaf');
      expect(find.byType(IngredientDetailScreen), findsOneWidget);
      expect(find.text('Bay leaf'), findsOneWidget);
      expect(find.text('No changes yet.'), findsOneWidget);
    });

    testWidgets('/history', (tester) async {
      await pumpRoute(tester, '/history');
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('No cooks yet. Start with Cook now.'), findsOneWidget);
    });

    testWidgets('/settings', (tester) async {
      await pumpRoute(tester, '/settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  testWidgets('the tab bar walks the four root screens', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/');

    await tester.tap(find.text('RECIPES'));
    await tester.pumpAndSettle();
    expect(find.byType(AllRecipesScreen), findsOneWidget);

    await tester.tap(find.text('STOCK'));
    await tester.pumpAndSettle();
    expect(find.byType(InventoryScreen), findsOneWidget);

    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);

    await tester.tap(find.text('COOK'));
    await tester.pumpAndSettle();
    expect(find.byType(CookNowScreen), findsOneWidget);
  });

  testWidgets('the gear opens Settings from a root screen', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/');

    await tester.tap(find.byKey(const ValueKey<String>('appbar-settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('a pushed screen hides the tab bar', (tester) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/recipes');

    expect(find.byType(PixelTabBar), findsOneWidget);

    await tester.tap(find.text('Sinangag'));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(find.byType(PixelTabBar), findsNothing);
  });
}
