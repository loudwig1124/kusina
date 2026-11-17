/// The 9-slice panel (`docs/07` §4): square corners, 2 au border, 2 au offset
/// shadow, 1 au inner highlight. A thin tone wrapper over [PixelBlock].
library;

import 'package:flutter/widgets.dart';

import 'pixel_block.dart';
import 'pixel_theme.dart';

enum PixelPanelTone {
  /// Cards, sheets, list panels: `white` fill.
  raised,

  /// Inset blocks: `cream_dark` fill.
  inset,

  /// Dialogs and toasts: `adobo` fill with a `banig` top edge.
  dark,
}

class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.tone = PixelPanelTone.raised,
    this.padding,
  });

  final Widget child;
  final PixelPanelTone tone;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return PixelBlock(
      fill: switch (tone) {
        PixelPanelTone.raised => PixelPalette.white,
        PixelPanelTone.inset => PixelPalette.creamDark,
        PixelPanelTone.dark => PixelPalette.adobo,
      },
      border: tone == PixelPanelTone.dark
          ? PixelPalette.banig
          : PixelPalette.adobo,
      highlight: tone == PixelPanelTone.raised ? PixelPalette.white : null,
      padding: padding,
      child: tone == PixelPanelTone.dark
          ? DefaultTextStyle.merge(
              style: const TextStyle(color: PixelPalette.cream),
              child: child,
            )
          : child,
    );
  }
}
