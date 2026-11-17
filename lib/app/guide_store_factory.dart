/// Builds the guide store for the app: the SQLite store when the repository
/// bundle has one, otherwise the Phase A in-memory store over the same ports.
///
/// This is the composition detail the router does not need to know: screens and
/// the engine only see the `GuideStore` seam.
library;

import '../domain/guide/guide_store.dart';
import 'di.dart';

GuideStore buildGuideStore(Repositories repositories) {
  final sqliteStore = repositories.guideStore;
  if (sqliteStore != null) {
    return sqliteStore;
  }
  return InMemoryGuideStore(
    recipeReader: repositories.recipes.findBySlug,
    statusReader: repositories.stock.getStatuses,
    ownedEquipmentReader: repositories.equipment.ownedIds,
    statusWriter: (code, to, reason, {cookingSessionId, note}) async {
      await repositories.stock.setStatus(
        ingredientCode: code,
        to: to,
        reason: reason,
        cookingSessionId: cookingSessionId,
        note: note,
      );
    },
  );
}
