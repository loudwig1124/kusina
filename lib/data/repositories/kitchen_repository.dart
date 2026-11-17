/// Single local kitchen profile contract (`docs/08` §5.2).
library;

import '../../domain/models/kitchen.dart';

abstract interface class KitchenRepository {
  Future<Kitchen> get();

  Future<Kitchen> rename(String name);
}
