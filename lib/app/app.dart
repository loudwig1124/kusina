/// MaterialApp.router + the pixel world: one theme, text scaling clamped at
/// 1.3x, and the composition root that owns the controllers (`docs/08` §3).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/guide/guide_engine.dart';
import '../features/guide/guide_controller.dart';
import '../features/history/history_controller.dart';
import '../features/kitchen/kitchen_controller.dart';
import '../features/recipes/recipes_controller.dart';
import '../features/stock/stock_controller.dart';
import '../ui/pixel/pixel_theme.dart';
import 'app_scope.dart';
import 'di.dart';
import 'guide_store_factory.dart';
import 'lifecycle.dart';
import 'router.dart';

class KusinaApp extends StatefulWidget {
  const KusinaApp({
    super.key,
    required this.repositories,
    this.initialLocation = Routes.cookNow,
    this.clock,
  });

  final Repositories repositories;

  /// Deep-link entry for widget tests; the app itself always opens on `/`.
  final String initialLocation;

  /// Injectable clock for tests; the app uses UTC wall time.
  final DateTime Function()? clock;

  @override
  State<KusinaApp> createState() => _KusinaAppState();
}

class _KusinaAppState extends State<KusinaApp> {
  late final RecipesController _recipes;
  late final StockController _stock;
  late final KitchenController _kitchen;
  late final GuideController _guide;
  late final HistoryController _history;
  late final GuideLifecycleObserver _lifecycle;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final repositories = widget.repositories;
    _recipes = RecipesController(
      recipeRepository: repositories.recipes,
      stockRepository: repositories.stock,
      equipmentRepository: repositories.equipment,
      availabilityService: repositories.availability,
    );
    _stock = StockController(stockRepository: repositories.stock);
    _kitchen = KitchenController(
      kitchenRepository: repositories.kitchen,
      equipmentRepository: repositories.equipment,
      onResetDemoData: repositories.resetDemoData,
    );
    final guideStore = buildGuideStore(repositories);
    _guide = GuideController(
      engine: LocalGuidedCookingEngine(store: guideStore),
      clock: widget.clock,
      onResetSessions: guideStore.clearSessions,
    );
    _history = HistoryController(
      sessions: guideStore.sessions,
      stockRepository: repositories.stock,
    );
    _lifecycle = GuideLifecycleObserver(guide: _guide)..attach();
    // Availability depends on stock and equipment: one listener each keeps every
    // badge honest after an Inventory tap or a Settings toggle.
    _stock.addListener(_refreshAvailability);
    _kitchen.addListener(_refreshAvailability);
    _router = buildRouter(
      repositories: repositories,
      initialLocation: widget.initialLocation,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait<void>(<Future<void>>[
      _recipes.load(),
      _stock.load(),
      _kitchen.load(),
      // A relaunch on SQLite finds the in-progress cook here.
      _guide.refreshActiveSession(),
    ]);
  }

  void _refreshAvailability() {
    _recipes.refresh();
  }

  @override
  void dispose() {
    _stock.removeListener(_refreshAvailability);
    _kitchen.removeListener(_refreshAvailability);
    _recipes.dispose();
    _stock.dispose();
    _kitchen.dispose();
    _lifecycle.detach();
    _guide.dispose();
    _history.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repositories: widget.repositories,
      recipes: _recipes,
      stock: _stock,
      kitchen: _kitchen,
      guide: _guide,
      history: _history,
      child: MaterialApp.router(
        title: 'Kusina',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        routerConfig: _router,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: PixelPalette.cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PixelPalette.clay,
        surface: PixelPalette.cream,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: PixelPalette.ink),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: PixelPalette.adobo,
      ),
    );
  }
}
