/// Shared "the data changed, refresh the screens" helper.
library;

import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';

/// Reloads the stock list and the availability badges after the guide (or the
/// resume card) writes through the repositories, and re-reads the active
/// session so the Cook Now card stays truthful.
Future<void> refreshAppData(BuildContext context) async {
  final scope = AppScope.of(context);
  await scope.stock.load();
  await scope.recipes.refresh();
  await scope.guide.refreshActiveSession();
}
