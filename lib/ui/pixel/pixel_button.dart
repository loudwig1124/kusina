/// Buttons (`docs/07` §4, §7.1).
///
/// One 56 dp primary action per screen, 48 dp for every other target; the hit
/// rect is the drawn rect. Disabled and loading states use palette colours, not
/// opacity. No animation runs indefinitely, so `pumpAndSettle` stays usable.
library;

import 'package:flutter/widgets.dart';

import 'pixel_block.dart';
import 'pixel_theme.dart';

enum PixelButtonKind { primary, secondary, destructive }

class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = PixelButtonKind.primary,
    this.loading = false,
    this.expand = true,
  });

  final String label;

  /// Null disables the button; the label still renders (e.g. the copy
  /// `Choose Pan-fry or Air-fry` while no method is picked).
  final VoidCallback? onPressed;
  final PixelButtonKind kind;
  final bool loading;
  final bool expand;

  bool get enabled => onPressed != null;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final kind = widget.kind;
    final fill = !enabled
        ? PixelPalette.creamDark
        : _pressed
        ? (kind == PixelButtonKind.primary
              ? PixelPalette.clayDark
              : PixelPalette.creamDark)
        : switch (kind) {
            PixelButtonKind.primary => PixelPalette.clay,
            PixelButtonKind.secondary => PixelPalette.cream,
            PixelButtonKind.destructive => PixelPalette.rust,
          };
    final border = !enabled
        ? PixelPalette.slate
        : switch (kind) {
            PixelButtonKind.primary => PixelPalette.clayDark,
            PixelButtonKind.secondary => PixelPalette.clay,
            PixelButtonKind.destructive => PixelPalette.rustDark,
          };
    final labelColor = !enabled
        ? PixelPalette.inkSoft
        : switch (kind) {
            PixelButtonKind.primary => PixelPalette.white,
            PixelButtonKind.secondary => PixelPalette.clayDark,
            PixelButtonKind.destructive => PixelPalette.white,
          };
    final height = kind == PixelButtonKind.primary ? 56.0 : 48.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onPressed : null,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: SizedBox(
          height: height,
          width: widget.expand ? double.infinity : null,
          child: Transform.translate(
            offset: Offset(0, _pressed ? 2 : 0),
            child: PixelBlock(
              fill: fill,
              border: border,
              withShadow: enabled && !_pressed,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: widget.loading
                    ? const _LoadingBlocks()
                    : Text(
                        widget.label.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: PixelType.actionLabel.copyWith(
                          color: labelColor,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three stepping blocks stand in for a spinner (`docs/07` §4).
class _LoadingBlocks extends StatelessWidget {
  const _LoadingBlocks();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < 3; index++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: SizedBox.square(
              dimension: 8 + index * 4,
              child: const ColoredBox(color: PixelPalette.white),
            ),
          ),
      ],
    );
  }
}
