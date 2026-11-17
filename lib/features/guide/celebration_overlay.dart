/// Completion celebration (`docs/07` §9.3 / docs/06 §7): the dish stamp, a full
/// progress bar and a four-frame stamp animation, shown once after the usage
/// review is confirmed.
library;

import 'package:flutter/material.dart';

import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_progress.dart';
import '../../ui/pixel/pixel_sprite.dart';
import '../../ui/pixel/pixel_theme.dart';
import 'guide_feedback.dart';

/// Shows the celebration and resolves when the cook dismisses it.
Future<void> showCelebration(
  BuildContext context, {
  required String recipeName,
  required String dishStampKey,
  required int usedItCount,
  required int usedItUpCount,
  required int didntUseCount,
  required int restockCorrections,
  GuideFeedback feedback = guideFeedback,
}) async {
  await feedback.celebrate();
  if (!context.mounted) {
    return;
  }
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: PixelPalette.adobo.withValues(alpha: 0.86),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, _, _) => CelebrationOverlay(
      recipeName: recipeName,
      dishStampKey: dishStampKey,
      usedItCount: usedItCount,
      usedItUpCount: usedItUpCount,
      didntUseCount: didntUseCount,
      restockCorrections: restockCorrections,
    ),
  );
}

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.recipeName,
    required this.dishStampKey,
    required this.usedItCount,
    required this.usedItUpCount,
    required this.didntUseCount,
    required this.restockCorrections,
  });

  final String recipeName;
  final String dishStampKey;
  final int usedItCount;
  final int usedItUpCount;
  final int didntUseCount;
  final int restockCorrections;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  static const List<double> _frames = <double>[1.6, 1.3, 1.0, 1.08];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Center(
      child: PixelCanvas(
        showBackdrop: false,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final frame = (_controller.value * _frames.length).floor().clamp(
              0,
              _frames.length - 1,
            );
            return Center(
              child: Padding(
                padding: EdgeInsets.all(unit * 6),
                child: PixelPanel(
                  tone: PixelPanelTone.dark,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'COOK COMPLETE',
                        textAlign: TextAlign.center,
                        style: PixelType.chromeMeta.copyWith(
                          fontSize: 18,
                          color: PixelPalette.banig,
                        ),
                      ),
                      SizedBox(height: unit * 3),
                      Center(
                        child: Transform.scale(
                          scale: _frames[frame],
                          child: PixelSprite(
                            spriteKey: widget.dishStampKey,
                            artUnits: 40,
                            semanticLabel: '${widget.recipeName} stamp',
                          ),
                        ),
                      ),
                      SizedBox(height: unit * 3),
                      Text(
                        widget.recipeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: PixelPalette.cream,
                        ),
                      ),
                      SizedBox(height: unit * 3),
                      PixelProgressBar(value: 1),
                      SizedBox(height: unit * 2),
                      Text(
                        '${widget.usedItCount} used · '
                        '${widget.usedItUpCount} used up · '
                        '${widget.didntUseCount} not used',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          color: PixelPalette.cream,
                        ),
                      ),
                      if (widget.restockCorrections > 0) ...<Widget>[
                        SizedBox(height: unit),
                        Text(
                          '${widget.restockCorrections} line'
                          '${widget.restockCorrections == 1 ? '' : 's'} '
                          'restocked first.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: PixelPalette.cream,
                          ),
                        ),
                      ],
                      SizedBox(height: unit * 2),
                      Text(
                        'Saved to History.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: PixelPalette.cream,
                        ),
                      ),
                      SizedBox(height: unit * 3),
                      PixelButton(
                        label: 'Back to Cook now',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
