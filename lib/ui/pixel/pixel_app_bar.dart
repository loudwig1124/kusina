/// App bar and tab bar chrome (`docs/07` §1.4, §4).
///
/// The app bar is 26 au tall with an optional back target and one settings
/// gear; both are 48 dp square hit rects. The tab bar is 24 au tall with four
/// 90 x 48 dp targets (icon + label).
library;

import 'package:flutter/widgets.dart';

import 'pixel_canvas.dart';
import 'pixel_sprite.dart';
import 'pixel_theme.dart';

class PixelAppBar extends StatelessWidget {
  const PixelAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.onSettings,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return SizedBox(
      height: unit * 26,
      child: Row(
        children: <Widget>[
          if (onBack != null)
            _IconTarget(
              key: const ValueKey<String>('appbar-back'),
              spriteKey: 'ui_back',
              semanticLabel: 'Back',
              onTap: onBack!,
            )
          else
            SizedBox(width: unit * 6),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelType.chromeMeta.copyWith(
                fontSize: 16,
                color: PixelPalette.clayDark,
              ),
            ),
          ),
          ?trailing,
          if (onSettings != null)
            _IconTarget(
              key: const ValueKey<String>('appbar-settings'),
              spriteKey: 'ui_gear',
              semanticLabel: 'Settings',
              onTap: onSettings!,
            ),
        ],
      ),
    );
  }
}

class _IconTarget extends StatelessWidget {
  const _IconTarget({
    super.key,
    required this.spriteKey,
    required this.semanticLabel,
    required this.onTap,
  });

  final String spriteKey;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 48,
          child: Center(child: PixelSprite(spriteKey: spriteKey, artUnits: 13)),
        ),
      ),
    );
  }
}

/// The four root destinations. Order is fixed: Cook, Recipes, Stock, History.
enum PixelTab {
  cook('COOK', 'tab_cook', '/'),
  recipes('RECIPES', 'tab_recipes', '/recipes'),
  stock('STOCK', 'tab_stock', '/stock'),
  history('HISTORY', 'tab_history', '/history');

  const PixelTab(this.label, this.spriteKey, this.route);

  final String label;
  final String spriteKey;
  final String route;
}

class PixelTabBar extends StatelessWidget {
  const PixelTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final barHeight = unit * 24 < 48 ? 48.0 : unit * 24;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(height: 2, color: PixelPalette.adobo),
        SizedBox(
          height: barHeight,
          child: Row(
            children: <Widget>[
              for (var index = 0; index < PixelTab.values.length; index++)
                Expanded(
                  child: _TabTarget(
                    tab: PixelTab.values[index],
                    active: index == currentIndex,
                    onTap: () => onTap(index),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabTarget extends StatelessWidget {
  const _TabTarget({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final PixelTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? PixelPalette.clayDark : PixelPalette.inkSoft;
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      child: GestureDetector(
        key: ValueKey<String>('tab-${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              PixelSprite(spriteKey: tab.spriteKey, artUnits: 11),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: PixelType.chromeMeta.copyWith(
                  fontSize: 10,
                  color: color,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 2,
                width: 28,
                color: active ? PixelPalette.clay : const Color(0x00000000),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
