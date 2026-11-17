/// Optional feedback hooks (`docs/07` §10). Phase D owns sound and haptics; the
/// guide calls this seam so adding them later needs no screen changes. Every
/// method is a safe no-op and never throws.
library;

class GuideFeedback {
  const GuideFeedback();

  /// A short, muteable celebration sound. Phase D.
  Future<void> celebrate() async {}

  /// A light tick on advance. Phase D.
  Future<void> tap() async {}
}

/// The app-wide instance; replace in Phase D with a real implementation.
const GuideFeedback guideFeedback = GuideFeedback();
