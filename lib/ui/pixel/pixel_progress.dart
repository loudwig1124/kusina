/// Progress bar and timer ring (`docs/07` §4).
///
/// Both are painted, both are integer-scaled, and the timer ring exposes its
/// four states plus the countdown digits it is given — time arithmetic lives in
/// the guide engine, not here.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pixel_canvas.dart';
import 'pixel_theme.dart';

/// The guide progress line: `cream_dark` track, `clay` fill with a 1 au `banig`
/// top highlight. The percentage is never drawn (`docs/07` §4).
class PixelProgressBar extends StatelessWidget {
  const PixelProgressBar({super.key, required this.value});

  /// 0..1.
  final double value;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final clamped = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      height: unit * 5,
      child: CustomPaint(
        painter: _ProgressPainter(value: clamped, unit: unit),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({required this.value, required this.unit});

  final double value;
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, paint..color = PixelPalette.creamDark);
    final filled = size.width * value;
    if (filled <= 0) {
      return;
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, filled, size.height),
      paint..color = PixelPalette.clay,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, filled, unit),
      paint..color = PixelPalette.banig,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.unit != unit;
}

/// Ring states (`docs/07` §9.4).
enum PixelTimerState {
  /// No timer running and none finished: track only.
  idle,

  /// Counting down: clay arc plus digits.
  running,

  /// Finished: full `calamansi_dark` ring with a check.
  done,

  /// Past zero: full `rust` ring plus the overrun copy.
  overrun,
}

/// A 56 au timer ring: tap targets the whole 112 dp disc.
class PixelTimerRing extends StatelessWidget {
  const PixelTimerRing({
    super.key,
    required this.state,
    required this.label,
    this.progress = 0,
    this.onTap,
    this.semanticLabel,
  });

  final PixelTimerState state;

  /// Countdown digits ("12:00") or the state's short copy ("Start timer").
  final String label;

  /// 0..1 remaining fraction; ignored unless [state] is running.
  final double progress;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final diameter = unit * 56;
    final ring = SizedBox.square(
      dimension: math.max(diameter, 48),
      child: CustomPaint(
        painter: _RingPainter(
          state: state,
          progress: progress.clamp(0.0, 1.0),
          unit: unit,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(unit * 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: PixelType.chromeMeta.copyWith(
                color: state == PixelTimerState.idle
                    ? PixelPalette.inkSoft
                    : PixelPalette.ink,
                fontSize: state == PixelTimerState.running ? 15 : 12,
              ),
            ),
          ),
        ),
      ),
    );
    final semantic = semanticLabel ?? '$label, ${state.name}';
    if (onTap == null) {
      return Semantics(label: semantic, child: ring);
    }
    return Semantics(
      button: true,
      label: semantic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ring,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.state,
    required this.progress,
    required this.unit,
  });

  final PixelTimerState state;
  final double progress;
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = unit * 3;
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = false
      ..color = PixelPalette.creamDark;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    final color = switch (state) {
      PixelTimerState.idle => null,
      PixelTimerState.running => PixelPalette.clay,
      PixelTimerState.done => PixelPalette.calamansiDark,
      PixelTimerState.overrun => PixelPalette.rust,
    };
    if (color == null) {
      return;
    }
    final sweep = state == PixelTimerState.running
        ? math.pi * 2 * progress
        : math.pi * 2;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..isAntiAlias = false
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.progress != progress ||
      oldDelegate.unit != unit;
}
