/// The shared pixel block painter: shadow, hard border, flat fill, optional
/// 1 au inner highlight. Every framed control (panel, button, chip, tab) draws
/// through this so edges stay square and land on the art grid.
library;

import 'package:flutter/widgets.dart';

import 'pixel_canvas.dart';
import 'pixel_theme.dart';

class PixelBlock extends StatelessWidget {
  const PixelBlock({
    super.key,
    required this.child,
    required this.fill,
    required this.border,
    this.highlight,
    this.withShadow = true,
    this.padding,
    this.borderUnits = 2,
    this.shadowUnits = 2,
  });

  final Widget child;
  final Color fill;
  final Color border;
  final Color? highlight;
  final bool withShadow;
  final EdgeInsets? padding;
  final double borderUnits;
  final double shadowUnits;

  @override
  Widget build(BuildContext context) {
    final scale = PixelScaleProvider.of(context);
    final unit = scale.au(1);
    final innerPadding =
        padding ??
        EdgeInsets.symmetric(horizontal: unit * 3, vertical: unit * 2);
    return CustomPaint(
      painter: PixelBlockPainter(
        fill: fill,
        border: border,
        highlight: highlight,
        unit: unit,
        borderUnits: borderUnits,
        shadowUnits: withShadow ? shadowUnits : 0,
      ),
      child: Padding(padding: innerPadding, child: child),
    );
  }
}

class PixelBlockPainter extends CustomPainter {
  const PixelBlockPainter({
    required this.fill,
    required this.border,
    required this.unit,
    this.highlight,
    this.borderUnits = 2,
    this.shadowUnits = 2,
  });

  final Color fill;
  final Color border;
  final Color? highlight;
  final double unit;
  final double borderUnits;
  final double shadowUnits;

  @override
  void paint(Canvas canvas, Size size) {
    final borderWidth = unit * borderUnits;
    final shadow = unit * shadowUnits;
    final body = Rect.fromLTWH(0, 0, size.width - shadow, size.height - shadow);
    final paint = Paint()..isAntiAlias = false;

    if (shadow > 0) {
      canvas.drawRect(
        body.shift(Offset(shadow, shadow)),
        paint..color = PixelPalette.adobo,
      );
    }
    canvas.drawRect(body, paint..color = border);
    final inner = Rect.fromLTWH(
      borderWidth,
      borderWidth,
      body.width - borderWidth * 2,
      body.height - borderWidth * 2,
    );
    canvas.drawRect(inner, paint..color = fill);

    final highlightColor = highlight;
    if (highlightColor != null &&
        inner.width > unit * 4 &&
        inner.height > unit * 4) {
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, inner.width, unit),
        paint..color = highlightColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, unit, inner.height),
        paint..color = highlightColor,
      );
    }
  }

  @override
  bool shouldRepaint(PixelBlockPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.highlight != highlight ||
      oldDelegate.unit != unit ||
      oldDelegate.borderUnits != borderUnits ||
      oldDelegate.shadowUnits != shadowUnits;
}
