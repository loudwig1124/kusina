/// One InheritedWidget carrying the repository bundle and the live controllers
/// (`docs/08` §3). Widgets read through here; nothing constructs a repository.
library;

import 'package:flutter/widgets.dart';

import 'di.dart';
import '../features/guide/guide_controller.dart';
import '../features/history/history_controller.dart';
import '../features/kitchen/kitchen_controller.dart';
import '../features/recipes/recipes_controller.dart';
import '../features/stock/stock_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.repositories,
    required this.recipes,
    required this.stock,
    required this.kitchen,
    required this.guide,
    required this.history,
    required super.child,
  });

  final Repositories repositories;
  final RecipesController recipes;
  final StockController stock;
  final KitchenController kitchen;

  /// The app-wide guided-cook controller: sessions, the resume card, the guide
  /// and the usage review all share it.
  final GuideController guide;
  final HistoryController history;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.repositories != repositories ||
      oldWidget.recipes != recipes ||
      oldWidget.stock != stock ||
      oldWidget.kitchen != kitchen ||
      oldWidget.guide != guide ||
      oldWidget.history != history;
}
