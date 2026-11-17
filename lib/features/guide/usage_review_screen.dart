/// Usage review (`docs/07` §7 screen 6, §8; `docs/09` §8): one tap per
/// ingredient, three choices per line, an "I have it" restock correction and a
/// single atomic confirm.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';

import '../../domain/guide/guide_models.dart';
import '../../domain/models/stock.dart';
import '../../ui/pixel/pixel_block.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_theme.dart';
import 'app_data_refresh.dart';
import 'celebration_overlay.dart';
import 'guide_controller.dart';

class UsageReviewScreen extends StatefulWidget {
  const UsageReviewScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<UsageReviewScreen> createState() => _UsageReviewScreenState();
}

class _UsageReviewScreenState extends State<UsageReviewScreen> {
  List<CompletionLine>? _lines;
  bool _opened = false;
  bool _loading = true;

  /// The celebration is shown once per confirmed cook.
  bool _celebrated = false;

  GuideController get _controller => AppScope.of(context).guide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!_opened) {
      _opened = true;
      await _controller.open(sessionId: widget.sessionId);
    }
    if (!mounted) {
      return;
    }
    await _reloadLines();
  }

  Future<void> _reloadLines() async {
    try {
      final lines = await _controller.loadReview();
      if (!mounted) {
        return;
      }
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } on EngineException {
      if (!mounted) {
        return;
      }
      setState(() {
        _lines = const <CompletionLine>[];
        _loading = false;
      });
    }
  }

  void _setChoice(int index, CompletionChoice choice) {
    final lines = _lines;
    if (lines == null ||
        !lines[index].effectiveAllowedChoices.contains(choice)) {
      return;
    }
    final next = List<CompletionLine>.of(lines);
    next[index] = next[index].copyWith(choice: choice);
    setState(() => _lines = next);
  }

  void _toggleRestock(int index) {
    final lines = _lines;
    if (lines == null || lines[index].status == StockStatus.have) {
      return;
    }
    final next = List<CompletionLine>.of(lines);
    next[index] = next[index].copyWith(
      restockToHave: !next[index].restockToHave,
    );
    setState(() => _lines = next);
  }

  Future<void> _confirm() async {
    final lines = _lines;
    if (lines == null || lines.isEmpty) {
      return;
    }
    final result = await _controller.complete(lines);
    if (!mounted) {
      return;
    }
    if (result != null && (result.isCompleted || result.isAlreadyCompleted)) {
      await refreshAppData(context);
      if (!mounted) {
        return;
      }
      // The celebration fires only for a fresh completion, never for a repeat.
      if (result.isCompleted && !_celebrated) {
        _celebrated = true;
        await showCelebration(
          context,
          recipeName: _controller.session?.recipeName ?? 'The dish',
          dishStampKey: _controller.recipe?.dishStampKey ?? 'dish_sinangag',
          usedItCount: result.usedItCount,
          usedItUpCount: result.usedItUpCount,
          didntUseCount: result.didntUseCount,
          restockCorrections: result.restockCorrections,
        );
      }
      if (!mounted) {
        return;
      }
      context.go('/');
      return;
    }
    // A stock edit between review and confirm invalidated a choice: refresh the
    // review and let the cook confirm again (`docs/09` §8.5 step 3).
    await _reloadLines();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: PixelPalette.adobo,
          content: Text(
            _controller.message ??
                'One choice no longer applies — review and confirm again.',
            style: const TextStyle(color: PixelPalette.cream, fontSize: 16),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final lines = _lines;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return PixelScreenScaffold(
          child: PixelPage(
            title: 'USAGE REVIEW',
            onBack: () => context.go('/'),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('What did you use?', style: PixelType.stepTitle),
                SizedBox(height: unit),
                Text(
                  'One tap per ingredient, then confirm once.',
                  style: PixelType.meta,
                ),
                SizedBox(height: unit),
                Text(
                  'Used it: Have → Low. Used it up: → Out.',
                  style: PixelType.meta,
                ),
                SizedBox(height: unit * 3),
              ],
            ),
            body: _loading && lines == null
                ? const Center(
                    child: Text('Loading the review…', style: PixelType.meta),
                  )
                : lines == null || lines.isEmpty
                ? Center(
                    child: Text(
                      _controller.message ??
                          'This cook is not at the review yet.',
                      style: PixelType.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.only(bottom: unit * 3),
                    children: <Widget>[
                      for (var index = 0; index < lines.length; index++)
                        Padding(
                          padding: EdgeInsets.only(bottom: unit * 3),
                          child: _ReviewLine(
                            line: lines[index],
                            onChoice: (choice) => _setChoice(index, choice),
                            onRestock: () => _toggleRestock(index),
                          ),
                        ),
                      Text('This stays on this phone.', style: PixelType.meta),
                    ],
                  ),
            footer: PixelButton(
              label: 'Confirm',
              loading: _controller.isBusy,
              onPressed: _controller.isBusy || lines == null || lines.isEmpty
                  ? null
                  : _confirm,
            ),
          ),
        );
      },
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({
    required this.line,
    required this.onChoice,
    required this.onRestock,
  });

  final CompletionLine line;
  final ValueChanged<CompletionChoice> onChoice;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final note = _noOpNote(line);
    return PixelPanel(
      key: ValueKey<String>('review-line-${line.ingredientCode}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(line.ingredientName, style: PixelType.rowLabel),
                    Text(
                      line.isRequired ? 'Required' : 'Optional',
                      style: PixelType.meta,
                    ),
                  ],
                ),
              ),
              PixelStatusChip(status: line.status, compact: true),
            ],
          ),
          if (line.status != StockStatus.have) ...<Widget>[
            SizedBox(height: unit * 2),
            PixelFilterChip(
              key: ValueKey<String>('review-restock-${line.ingredientCode}'),
              label: line.restockToHave ? 'I have it ✓' : 'I have it',
              selected: line.restockToHave,
              onTap: onRestock,
            ),
          ],
          SizedBox(height: unit * 2),
          Row(
            children: <Widget>[
              for (
                var index = 0;
                index < reviewChoices.length;
                index++
              ) ...<Widget>[
                if (index > 0) SizedBox(width: unit * 2),
                Expanded(
                  child: _ChoiceChip(
                    key: ValueKey<String>(
                      'review-choice-${line.ingredientCode}-'
                      '${reviewChoices[index].name}',
                    ),
                    label: reviewChoices[index].label,
                    selected: line.choice == reviewChoices[index],
                    enabled: line.effectiveAllowedChoices.contains(
                      reviewChoices[index],
                    ),
                    semanticLabel: _choiceSemanticLabel(
                      line,
                      reviewChoices[index],
                    ),
                    onTap: () => onChoice(reviewChoices[index]),
                  ),
                ),
              ],
            ],
          ),
          if (note != null) ...<Widget>[
            SizedBox(height: unit),
            Text(note, style: PixelType.meta),
          ],
          if (line.restockToHave) ...<Widget>[
            SizedBox(height: unit),
            Text(
              'Restock is recorded first, then the usage.',
              style: PixelType.meta,
            ),
          ],
        ],
      ),
    );
  }

  /// "already out" is announced for the disabled Used it chip (`docs/07` §8.1).
  static String? _choiceSemanticLabel(
    CompletionLine line,
    CompletionChoice choice,
  ) {
    if (choice != CompletionChoice.usedIt) {
      return null;
    }
    return switch (line.effectiveStatus) {
      StockStatus.out => 'Used it, already out',
      StockStatus.low => 'Used it, already low',
      _ => null,
    };
  }

  static String? _noOpNote(CompletionLine line) {
    if (line.choice == CompletionChoice.didntUse) {
      return null;
    }
    final effective = line.effectiveStatus;
    if (line.choice == CompletionChoice.usedIt &&
        effective == StockStatus.low) {
      return 'Already low: this choice writes nothing.';
    }
    if (line.choice == CompletionChoice.usedItUp &&
        effective == StockStatus.out) {
      return 'Already out: this choice writes nothing.';
    }
    return null;
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fill = !enabled
        ? PixelPalette.creamDark
        : selected
        ? PixelPalette.clay
        : PixelPalette.cream;
    final border = !enabled
        ? PixelPalette.slate
        : selected
        ? PixelPalette.clayDark
        : PixelPalette.adobo;
    final textColor = !enabled
        ? PixelPalette.slate
        : selected
        ? PixelPalette.white
        : PixelPalette.ink;
    final chip = SizedBox(
      height: 48,
      child: PixelBlock(
        fill: fill,
        border: border,
        withShadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelType.statusLabel.copyWith(color: textColor),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel ?? label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: chip,
      ),
    );
  }
}
