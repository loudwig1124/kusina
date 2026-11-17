/// Palette tokens and text styles for the pixel UI (`docs/07` §2-§3,
/// `design/palette.json`).
///
/// One source of truth for colour: every widget takes colours from here, never
/// a literal hex. The palette is exactly 16 colours; a new colour needs a new
/// contrast row in the spec.
library;

import 'package:flutter/widgets.dart';

/// The 16 locked colours. Names are semantic roles, not palette positions.
abstract final class PixelPalette {
  static const Color ink = Color(0xFF1B1410);
  static const Color inkSoft = Color(0xFF4A3A2C);
  static const Color adobo = Color(0xFF2A1E18);
  static const Color cream = Color(0xFFF6EAD3);
  static const Color creamDark = Color(0xFFE4D1B2);
  static const Color clay = Color(0xFFA8432B);
  static const Color clayDark = Color(0xFF7C2E1C);
  static const Color banig = Color(0xFFD9A23F);
  static const Color calamansi = Color(0xFF7E9C33);
  static const Color calamansiDark = Color(0xFF4A6416);
  static const Color amber = Color(0xFFE0A32B);
  static const Color amberDark = Color(0xFF7A4E08);
  static const Color rust = Color(0xFFB23A2F);
  static const Color rustDark = Color(0xFF7A2119);
  static const Color slate = Color(0xFF8A9299);
  static const Color white = Color(0xFFFFF8EA);
}

/// Type scale from `docs/07` §3.2.
///
/// Chrome (headings, section labels, button labels, numerals) uses a monospace
/// face: it stands in for the 5x7 bitmap atlas until that PNG ships, and it
/// never sets prose. Body copy is the system sans at >= 18 sp with line height
/// 1.35, and the four locked status labels / three availability badges stay in
/// title-case system sans so they read verbatim.
abstract final class PixelType {
  /// Screen heading: "COOK NOW".
  static const TextStyle heading = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>['Courier'],
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    color: PixelPalette.ink,
  );

  /// Section label: "INGREDIENTS", "COOKING METHOD".
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>['Courier'],
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    color: PixelPalette.inkSoft,
  );

  /// Chrome meta line (counts, equipment line): bitmap 1x equivalent.
  static const TextStyle chromeMeta = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>['Courier'],
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: PixelPalette.inkSoft,
  );

  /// Action-button label.
  static const TextStyle actionLabel = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>['Courier'],
    fontSize: 16,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
  );

  /// Step card title.
  static const TextStyle stepTitle = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: PixelPalette.ink,
  );

  /// Instruction / body prose: >= 18 sp, line height >= 1.35.
  static const TextStyle body = TextStyle(
    fontSize: 18,
    height: 1.35,
    color: PixelPalette.ink,
  );

  /// Dialog and panel body prose.
  static const TextStyle bodySmall = TextStyle(
    fontSize: 16,
    height: 1.35,
    color: PixelPalette.ink,
  );

  /// Row / ingredient label.
  static const TextStyle rowLabel = TextStyle(
    fontSize: 16,
    height: 1.3,
    color: PixelPalette.ink,
  );

  /// Secondary meta line.
  static const TextStyle meta = TextStyle(
    fontSize: 14,
    height: 1.3,
    color: PixelPalette.inkSoft,
  );

  /// Locked status/badge label: system sans bold, title case, 14 sp.
  static const TextStyle statusLabel = TextStyle(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );
}

/// Status colours and glyphs. Colour is never the only signal: every state
/// ships with a shape and a label (`docs/07` §2.2).
class PixelStatusStyle {
  const PixelStatusStyle({
    required this.fill,
    required this.text,
    required this.glyph,
  });

  final Color fill;
  final Color text;

  /// Icon shape: `✓`, `◐`, `✕`, `?`.
  final String glyph;
}

/// Spacing helpers in art units (1 au = `k / dpr` dp at an integer scale).
abstract final class PixelSpacing {
  /// Content margin left/right: 6 au (12 dp at the reference device).
  static const double contentMarginAu = 6;

  /// Standard gap between stacked blocks.
  static const double blockGapAu = 4;
}
