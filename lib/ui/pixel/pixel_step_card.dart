/// Step card (`docs/07` §9.1): order badge, kind, title, instruction, detail,
/// divider, timer row and caution row inside one 9-slice panel.
///
/// Presentation only: it renders what the guide hands it and never decides
/// which step comes next.
library;

import 'package:flutter/widgets.dart';

import '../../domain/models/recipe.dart';
import 'pixel_canvas.dart';
import 'pixel_panel.dart';
import 'pixel_sprite.dart';
import 'pixel_theme.dart';

class PixelStepCard extends StatelessWidget {
  const PixelStepCard({
    super.key,
    required this.stepNumber,
    required this.kind,
    required this.instruction,
    this.detail,
    this.spriteKey,
    this.timerLabel,
    this.caution,
    this.trailing,
  });

  final int stepNumber;
  final StepKind kind;
  final String instruction;
  final String? detail;
  final String? spriteKey;

  /// Null renders "No timer on this step".
  final String? timerLabel;
  final String? caution;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox.square(
                dimension: unit * 16,
                child: ColoredBox(
                  color: PixelPalette.clay,
                  child: Center(
                    child: Text(
                      '$stepNumber',
                      style: PixelType.chromeMeta.copyWith(
                        color: PixelPalette.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: unit * 3),
              Expanded(
                child: Text(
                  kind.name.toUpperCase(),
                  style: PixelType.sectionLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: unit * 3),
          Text(instruction, style: PixelType.body),
          if (detail != null) ...<Widget>[
            SizedBox(height: unit * 2),
            Text(detail!, style: PixelType.meta),
          ],
          SizedBox(height: unit * 3),
          Container(height: unit, color: PixelPalette.creamDark),
          SizedBox(height: unit * 2),
          Row(
            children: <Widget>[
              if (spriteKey != null) ...<Widget>[
                PixelSprite(spriteKey: spriteKey!, artUnits: 8),
                SizedBox(width: unit * 2),
              ],
              Expanded(
                child: Text(
                  timerLabel ?? 'No timer on this step',
                  style: PixelType.meta,
                ),
              ),
            ],
          ),
          if (caution != null) ...<Widget>[
            SizedBox(height: unit * 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '!',
                  style: PixelType.statusLabel.copyWith(
                    color: PixelPalette.amberDark,
                  ),
                ),
                SizedBox(width: unit * 2),
                Expanded(
                  child: Text(
                    caution!,
                    style: PixelType.meta.copyWith(
                      color: PixelPalette.amberDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
