/// The integer art scale and the canvas that applies it (`docs/07` §1.1-§1.3).
///
/// The art layer is always an integer number of device pixels per art unit:
/// `k = max(1, floor(screenWidthPx / 180))`, so `1 au = k / dpr` dp and the
/// 180 au art width lands on `180 * k` device pixels exactly. No `FittedBox`,
/// no fractional `Transform.scale`, no resized PNGs.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pixel_theme.dart';

/// Immutable scale for one layout pass.
@immutable
class PixelScale {
  const PixelScale({required this.factor, required this.devicePixelRatio});

  /// `k`: device pixels per art unit.
  final int factor;
  final double devicePixelRatio;

  /// Logical art width (dp) for a given screen width in device pixels.
  static PixelScale forViewport({
    required double widthPx,
    required double devicePixelRatio,
  }) {
    final factor = math.max(1, (widthPx / 180).floor());
    return PixelScale(factor: factor, devicePixelRatio: devicePixelRatio);
  }

  static PixelScale of(BuildContext context) {
    final media = MediaQuery.of(context);
    final widthPx = media.size.width * media.devicePixelRatio;
    return forViewport(
      widthPx: widthPx,
      devicePixelRatio: media.devicePixelRatio,
    );
  }

  /// Converts [artUnits] to dp at this scale.
  double au(num artUnits) => artUnits * factor / devicePixelRatio;

  /// The rendered art width in dp (180 au).
  double get artWidth => au(180);

  /// The rendered art width in device pixels; always an integer multiple.
  double get artWidthPx => 180.0 * factor;

  @override
  bool operator ==(Object other) =>
      other is PixelScale &&
      other.factor == factor &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => Object.hash(factor, devicePixelRatio);

  @override
  String toString() => 'PixelScale(k: $factor, dpr: $devicePixelRatio)';
}

/// Exposes the current [PixelScale] to descendants so widgets resolve art units
/// without each one recomputing the scale from MediaQuery.
class PixelScaleProvider extends InheritedWidget {
  const PixelScaleProvider({
    super.key,
    required this.scale,
    required super.child,
  });

  final PixelScale scale;

  static PixelScale of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<PixelScaleProvider>();
    return provider?.scale ?? PixelScale.of(context);
  }

  @override
  bool updateShouldNotify(PixelScaleProvider oldWidget) =>
      oldWidget.scale != scale;
}

/// Page frame: cream background, a centred 180 au content column, and a
/// decorative art backdrop that never stretches with the viewport.
class PixelCanvas extends StatelessWidget {
  const PixelCanvas({super.key, required this.child, this.showBackdrop = true});

  final Widget child;
  final bool showBackdrop;

  @override
  Widget build(BuildContext context) {
    final scale = PixelScale.of(context);
    return ColoredBox(
      color: PixelPalette.cream,
      child: PixelScaleProvider(
        scale: scale,
        child: Center(
          child: SizedBox(
            width: scale.artWidth,
            child: Stack(
              children: <Widget>[
                if (showBackdrop)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _BackdropPainter(scale: scale),
                      ),
                    ),
                  ),
                Positioned.fill(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banig-weave bands behind the content: two horizontal rules and a soft
/// checker strip, drawn in whole art units so every edge sits on the pixel grid.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.scale});

  final PixelScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = PixelPalette.creamDark;
    final bandHeight = scale.au(2);
    final bandY = scale.au(12);
    for (double y = bandY; y < size.height; y += scale.au(12)) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, bandHeight), paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, scale.au(1)),
      Paint()..color = PixelPalette.creamDark,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.scale != scale;
}
