/// Inventory state: one tri-state per ingredient, written one legal stock
/// event per tap. No quantities, ever (`docs/07` §5.3).
library;

import 'package:flutter/foundation.dart';

import '../../data/repositories/stock_repository.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/stock.dart';
import '../../domain/rules/stock_rules.dart';

class StockController extends ChangeNotifier {
  StockController({required this.stockRepository});

  final StockRepository stockRepository;

  bool _loading = true;
  Object? _error;
  List<Ingredient> _ingredients = const <Ingredient>[];
  Map<String, StockStatus> _statuses = const <String, StockStatus>{};
  String? _lastSavedIngredientCode;

  bool get isLoading => _loading;
  Object? get error => _error;
  List<Ingredient> get ingredients => _ingredients;
  Map<String, StockStatus> get statuses => _statuses;

  /// Set after a successful write so the screen can show the toast
  /// "Saved. No numbers to type.".
  String? get lastSavedIngredientCode => _lastSavedIngredientCode;

  StockStatus statusFor(String ingredientCode) =>
      _statuses[ingredientCode] ?? StockStatus.unknown;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _ingredients = await stockRepository.listIngredients();
      _statuses = await stockRepository.getStatuses(
        _ingredients.map((ingredient) => ingredient.code),
      );
      _loading = false;
    } catch (error) {
      _error = error;
      _loading = false;
    }
    notifyListeners();
  }

  /// Writes the status the cook tapped. Returns true when an event was written
  /// (false for a no-op).
  Future<bool> setStatus(String ingredientCode, StockStatus to) async {
    final from = statusFor(ingredientCode);
    final hasPriorEvent = (await stockRepository.listEvents(
      ingredientCode: ingredientCode,
      limit: 1,
    )).isNotEmpty;
    final reason = StockRules.reasonForManualEdit(
      from: from,
      to: to,
      isFirstRecord: !hasPriorEvent,
    );
    if (reason == null) {
      return false;
    }
    await stockRepository.setStatus(
      ingredientCode: ingredientCode,
      to: to,
      reason: reason,
    );
    _statuses = <String, StockStatus>{..._statuses, ingredientCode: to};
    _lastSavedIngredientCode = ingredientCode;
    notifyListeners();
    return true;
  }

  Future<List<StockEvent>> eventsFor(String ingredientCode) =>
      stockRepository.listEvents(ingredientCode: ingredientCode);
}
