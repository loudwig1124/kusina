/// The explicit method control (`docs/07` §7.1): two 156 x 72 dp buttons, each
/// with its own availability badge, in one row.
///
/// Presentation only. It renders the state it is given and reports taps; it
/// never selects a method on its own and never falls back to the other method.
library;

import 'package:flutter/widgets.dart';

import '../../domain/rules/availability_service.dart';
import 'pixel_availability_presentation.dart';
import 'pixel_block.dart';
import 'pixel_canvas.dart';
import 'pixel_sprite.dart';
import 'pixel_theme.dart';

/// One selectable method with its own availability, computed for that method's
/// path.
class PixelMethodOption {
  const PixelMethodOption({
    required this.key,
    required this.label,
    required this.iconKey,
    required this.availability,
    this.isDisabled = false,
  });

  final String key;
  final String label;
  final String iconKey;
  final AvailabilityState? availability;

  /// Disabled only while an in-progress session pins the method.
  final bool isDisabled;
}

class PixelMethodControl extends StatelessWidget {
  const PixelMethodControl({
    super.key,
    required this.options,
    required this.onSelected,
    this.selectedKey,
  });

  final List<PixelMethodOption> options;
  final ValueChanged<String> onSelected;
  final String? selectedKey;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Row(
      children: <Widget>[
        for (var index = 0; index < options.length; index++) ...<Widget>[
          if (index > 0) SizedBox(width: unit * 4),
          Expanded(
            child: _MethodButton(
              option: options[index],
              selected: options[index].key == selectedKey,
              onTap: options[index].isDisabled
                  ? null
                  : () => onSelected(options[index].key),
            ),
          ),
        ],
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final PixelMethodOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fill = disabled
        ? PixelPalette.creamDark
        : selected
        ? PixelPalette.clay
        : PixelPalette.cream;
    final border = disabled
        ? PixelPalette.slate
        : selected
        ? PixelPalette.clayDark
        : PixelPalette.slate;
    final textColor = disabled
        ? PixelPalette.inkSoft
        : selected
        ? PixelPalette.white
        : PixelPalette.ink;
    final availability = option.availability;

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: availability == null
          ? option.label
          : '${option.label}, ${availability.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: PixelBlock(
            fill: fill,
            border: border,
            withShadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    PixelSprite(spriteKey: option.iconKey, artUnits: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PixelType.statusLabel.copyWith(
                          fontSize: 15,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (selected)
                      Text(
                        '✓',
                        style: PixelType.statusLabel.copyWith(color: textColor),
                      ),
                  ],
                ),
                if (availability != null) ...<Widget>[
                  const SizedBox(height: 6),
                  _MethodBadge(state: availability),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.state});

  final AvailabilityState state;

  @override
  Widget build(BuildContext context) {
    final style = state.pixelStyle;
    return PixelBlock(
      fill: style.fill,
      border: PixelPalette.adobo,
      withShadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        state.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PixelType.statusLabel.copyWith(fontSize: 13, color: style.text),
      ),
    );
  }
}
