/// Status chips, availability badges and filter chips (`docs/07` §4-§5).
///
/// Colour is never the only signal: each stock chip carries a shape glyph and
/// the locked title-case label. Every tappable chip draws at its hit size of at
/// least 48 dp (`docs/07` rule 6).
library;

import 'package:flutter/widgets.dart';

import '../../domain/models/stock.dart';
import '../../domain/rules/availability_service.dart';
import 'pixel_availability_presentation.dart';
import 'pixel_block.dart';
import 'pixel_theme.dart';

/// Stock status chip. Used read-only on recipe detail (compact) and as the
/// Inventory 2x2 grid control (`grid`).
class PixelStatusChip extends StatelessWidget {
  const PixelStatusChip({
    super.key,
    required this.status,
    this.selected = true,
    this.onTap,
    this.compact = false,
  });

  final StockStatus status;

  /// False renders the "unselected" cream face used by the Inventory grid.
  final bool selected;
  final VoidCallback? onTap;

  /// Compact = recipe-detail read-only chip (68 au); otherwise the 76 au grid
  /// chip. Both are at least 48 dp tall.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = status.pixelStyle;
    return PixelChipSurface(
      label: selected ? status.label : status.label,
      glyph: selected ? style.glyph : null,
      fill: selected ? style.fill : PixelPalette.cream,
      border: selected ? PixelPalette.adobo : PixelPalette.slate,
      textColor: selected ? style.text : PixelPalette.inkSoft,
      onTap: onTap,
      semanticLabel: '${status.label}${selected ? '' : ', not set'}',
      minHeight: 48,
      horizontalPadding: compact ? 8 : 12,
      labelWidth: compact ? 68 : null,
    );
  }
}

/// Recipe-level availability badge: Ready / Probably have / Missing.
class PixelAvailabilityBadge extends StatelessWidget {
  const PixelAvailabilityBadge({
    super.key,
    required this.state,
    this.minWidth = 88,
  });

  final AvailabilityState state;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final style = state.pixelStyle;
    return PixelChipSurface(
      label: state.label,
      fill: style.fill,
      border: PixelPalette.adobo,
      textColor: style.text,
      minHeight: 34,
      minWidth: minWidth,
      horizontalPadding: 8,
      semanticLabel: state.label,
    );
  }
}

/// Filter / category chip (All, Ready, Produce, ...).
class PixelFilterChip extends StatelessWidget {
  const PixelFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PixelChipSurface(
      label: label,
      fill: selected ? PixelPalette.clay : PixelPalette.cream,
      border: selected ? PixelPalette.clayDark : PixelPalette.adobo,
      textColor: selected ? PixelPalette.white : PixelPalette.ink,
      onTap: onTap,
      minHeight: 48,
      horizontalPadding: 12,
      semanticLabel: label,
      labelStyle: PixelType.rowLabel.copyWith(
        fontWeight: FontWeight.w700,
        color: selected ? PixelPalette.white : PixelPalette.ink,
      ),
    );
  }
}

/// Shared chip frame: hard border, flat fill, optional glyph and label.
class PixelChipSurface extends StatelessWidget {
  const PixelChipSurface({
    super.key,
    required this.label,
    required this.fill,
    required this.border,
    required this.textColor,
    this.glyph,
    this.onTap,
    this.minHeight = 48,
    this.minWidth = 48,
    this.horizontalPadding = 10,
    this.labelWidth,
    this.semanticLabel,
    this.labelStyle,
  });

  final String label;
  final Color fill;
  final Color border;
  final Color textColor;
  final String? glyph;
  final VoidCallback? onTap;
  final double minHeight;
  final double minWidth;
  final double horizontalPadding;

  /// Fixed label width for the recipe-detail status chip (68 au).
  final double? labelWidth;
  final String? semanticLabel;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (glyph != null) ...<Widget>[
          Text(glyph!, style: PixelType.statusLabel.copyWith(color: textColor)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                labelStyle ?? PixelType.statusLabel.copyWith(color: textColor),
          ),
        ),
      ],
    );

    final chip = SizedBox(
      height: minHeight,
      width: labelWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
        child: PixelBlock(
          fill: fill,
          border: border,
          withShadow: false,
          borderUnits: 2,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Center(widthFactor: 1, child: content),
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(
        label: semanticLabel ?? label,
        child: ExcludeSemantics(child: chip),
      );
    }
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: chip,
      ),
    );
  }
}
