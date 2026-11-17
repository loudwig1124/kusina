/// Session read contract (`docs/08` §5.2). The write path lives on the guide
/// store seam (`lib/domain/guide/guide_store.dart`), which owns the completion
/// transaction; this contract is the read side screens and tests use.
library;

import '../../domain/guide/guide_models.dart';

abstract interface class SessionRepository {
  Future<GuidedSession?> loadActiveSession();

  Future<GuidedSession?> loadSession(String sessionId);

  Future<List<GuidedSession>> history({int limit = 50, int offset = 0});
}
