/// Presentation mapping for the locked stock and availability labels
/// (`docs/07` §2.2, §5.1; `design/palette.json` `states` / `availability`).
///
/// Kept out of the domain so the pure rules never carry colours, and out of
/// widgets so no screen invents its own pair.
library;

import '../../domain/models/stock.dart';
import '../../domain/rules/availability_service.dart';
import 'pixel_theme.dart';

extension StockStatusPixelStyle on StockStatus {
  PixelStatusStyle get pixelStyle => switch (this) {
    StockStatus.have => const PixelStatusStyle(
      fill: PixelPalette.calamansi,
      text: PixelPalette.ink,
      glyph: '✓',
    ),
    StockStatus.low => const PixelStatusStyle(
      fill: PixelPalette.amber,
      text: PixelPalette.ink,
      glyph: '◐',
    ),
    StockStatus.out => const PixelStatusStyle(
      fill: PixelPalette.rust,
      text: PixelPalette.white,
      glyph: '✕',
    ),
    StockStatus.unknown => const PixelStatusStyle(
      fill: PixelPalette.creamDark,
      text: PixelPalette.inkSoft,
      glyph: '?',
    ),
  };
}

extension AvailabilityStatePresentation on AvailabilityState {
  /// Locked title-case badge label: Ready / Probably have / Missing.
  String get label => switch (this) {
    AvailabilityState.ready => 'Ready',
    AvailabilityState.needsConfirmation => 'Probably have',
    AvailabilityState.blocked => 'Missing',
  };

  PixelStatusStyle get pixelStyle => switch (this) {
    AvailabilityState.ready => const PixelStatusStyle(
      fill: PixelPalette.calamansi,
      text: PixelPalette.ink,
      glyph: '',
    ),
    AvailabilityState.needsConfirmation => const PixelStatusStyle(
      fill: PixelPalette.amber,
      text: PixelPalette.ink,
      glyph: '?',
    ),
    AvailabilityState.blocked => const PixelStatusStyle(
      fill: PixelPalette.rust,
      text: PixelPalette.white,
      glyph: '✕',
    ),
  };
}
