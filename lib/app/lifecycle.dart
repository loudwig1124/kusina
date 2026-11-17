/// App lifecycle wiring for the guided cook (`docs/08` §3.1, `docs/09` §6.4).
///
/// Backgrounding persists `last_seen_at` (so `done` vs `overrun` is derivable)
/// and releases the wake lock; coming back derives the engine's resume sentence
/// and marks the session seen. The engine never auto-advances here.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../features/guide/guide_controller.dart';

class GuideLifecycleObserver with WidgetsBindingObserver {
  GuideLifecycleObserver({required this.guide});

  final GuideController guide;

  bool _attached = false;

  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_safely(guide.onResumeFromBackground));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_safely(guide.onPause));
    }
  }

  /// Lifecycle callbacks cannot surface errors; the controller records them.
  static Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Nothing to do: the guide keeps its last known state.
    }
  }
}
