/// Guided cook (`docs/07` §7 screen 5, §9): one step at a time, a step card, an
/// advisory timer, tap-to-advance only, and an explicit abandon.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/guide/guide_models.dart';
import '../../domain/guide/guide_rules.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_progress.dart';
import '../../ui/pixel/pixel_sprite.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_step_card.dart';
import '../../ui/pixel/pixel_theme.dart';
import 'guide_controller.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({
    super.key,
    required this.sessionId,
    this.recipeSlug,
    this.methodKey,
    this.guideAnyway = false,
  });

  /// A real session id, or [startSessionId] to start from the recipe screen.
  final String sessionId;
  final String? recipeSlug;
  final String? methodKey;
  final bool guideAnyway;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  bool _opened = false;
  GuideController? _guide;

  GuideController get _controller => _guide ?? AppScope.of(context).guide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guide = AppScope.of(context).guide;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    // Leaving the guide stops the display ticker; the session keeps its
    // absolute timer start and re-derives on return. The reference was captured
    // in didChangeDependencies: ancestor lookups are unsafe while disposing.
    _guide?.pauseTicking();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opened) {
      return;
    }
    _opened = true;
    final review = await _controller.open(
      sessionId: widget.sessionId,
      recipeSlug: widget.recipeSlug,
      methodKey: widget.methodKey,
      guideAnyway: widget.guideAnyway,
    );
    if (!mounted) {
      return;
    }
    if (review) {
      _goToReview();
    }
  }

  void _goToReview() {
    final session = _controller.session;
    if (session == null || !mounted) {
      return;
    }
    context.pushReplacement('/guide/${session.id}/review');
  }

  Future<void> _advance() async {
    await _controller.advance();
    if (!mounted) {
      return;
    }
    final session = _controller.session;
    if (session != null && session.isReview) {
      _goToReview();
    }
  }

  Future<void> _close() async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _LeaveDialog(
        recipeName: _controller.session?.recipeName ?? 'this cook',
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'abandon') {
      await _controller.abandon();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: PixelPalette.adobo,
            content: Text(
              'Cook abandoned. No stock changed.',
              style: TextStyle(color: PixelPalette.cream, fontSize: 16),
            ),
            duration: Duration(seconds: 2),
          ),
        );
    }
    if (!mounted) {
      return;
    }
    // Leaving keeps the session in progress and rewrites nothing.
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final session = controller.session;
        if (controller.isLoading && session == null) {
          return const PixelScreenScaffold(
            child: PixelPage(
              title: 'GUIDE',
              body: Center(
                child: Text('Loading the cook…', style: PixelType.bodySmall),
              ),
            ),
          );
        }
        if (session == null) {
          return PixelScreenScaffold(
            child: PixelPage(
              title: 'GUIDE',
              onBack: () => context.go('/'),
              body: Center(
                child: PixelPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('NO COOK HERE', style: PixelType.sectionLabel),
                      const SizedBox(height: 8),
                      Text(
                        controller.message ??
                            'That cook is no longer available. Start again '
                                'from a recipe.',
                        style: PixelType.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (session.isReview) {
          return PixelScreenScaffold(
            child: PixelPage(
              title: 'GUIDE',
              onBack: _close,
              body: Center(
                child: PixelPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'STEP ${session.totalSteps} OF '
                        '${session.totalSteps}',
                        style: PixelType.chromeMeta,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'That was the last step.',
                        style: PixelType.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              footer: PixelButton(label: 'Review', onPressed: _goToReview),
            ),
          );
        }
        return _buildStep(context, controller, session);
      },
    );
  }

  Widget _buildStep(
    BuildContext context,
    GuideController controller,
    GuidedSession session,
  ) {
    final unit = PixelScaleProvider.of(context).au(1);
    final step = controller.stepView!;
    final isLastStep = step.stepNumber == session.totalSteps;
    final timer = controller.timer;
    final pinnedDuration = session.path
        .step(step.stepNumber)
        ?.snapshot
        .durationSeconds;
    final stepTimerLabel = pinnedDuration == null
        ? 'No timer on this step'
        : timer.phase == TimerPhase.idle
        ? '${(pinnedDuration / 60).round()} min timer — tap the ring below'
        : timerCopy(timer);

    return PixelScreenScaffold(
      child: PixelPage(
        title: 'GUIDE',
        onBack: _close,
        trailing: Padding(
          padding: EdgeInsets.only(right: unit),
          child: Text(
            'STEP ${step.stepNumber} OF ${step.totalSteps}',
            style: PixelType.chromeMeta,
          ),
        ),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    session.recipeName,
                    style: PixelType.stepTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(controller.methodLabel, style: PixelType.meta),
              ],
            ),
            SizedBox(height: unit),
            PixelProgressBar(value: step.progressFraction),
            SizedBox(height: unit),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.only(bottom: unit * 3),
          children: <Widget>[
            if (controller.resumeCopy != null) ...<Widget>[
              _ResumeBanner(
                copy: controller.resumeCopy!,
                onDismiss: controller.dismissResumeBanner,
              ),
              SizedBox(height: unit * 3),
            ],
            if (session.startedWithoutAvailability) ...<Widget>[
              _GuideAnywayBanner(codes: session.missingCodes),
              SizedBox(height: unit * 3),
            ],
            _SceneStrip(
              stepSpriteKey: step.spriteKey,
              equipmentCode: step.equipmentCode,
              dishStampKey: controller.recipe?.dishStampKey,
            ),
            SizedBox(height: unit * 3),
            PixelStepCard(
              stepNumber: step.stepNumber,
              kind: step.kind,
              instruction: step.instruction,
              detail: step.detail,
              spriteKey: step.spriteKey,
              caution: step.caution,
              timerLabel: stepTimerLabel,
            ),
            SizedBox(height: unit * 3),
            _TimerPanel(controller: controller, step: step),
            if (controller.message != null) ...<Widget>[
              SizedBox(height: unit * 3),
              Text(
                controller.message!,
                style: PixelType.meta.copyWith(color: PixelPalette.rustDark),
              ),
            ],
            SizedBox(height: unit * 3),
            Text(
              'Tap to advance. Timers are advice; the app never moves a step.',
              style: PixelType.meta,
            ),
          ],
        ),
        footer: PixelButton(
          label: isLastStep ? 'Finish' : 'Continue',
          loading: controller.isBusy,
          onPressed: controller.isBusy ? null : _advance,
        ),
      ),
    );
  }
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({required this.controller, required this.step});

  final GuideController controller;
  final StepView step;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final timer = controller.timer;
    final session = controller.session;
    final duration = session?.path
        .step(step.stepNumber)
        ?.snapshot
        .durationSeconds;
    final phase = timer.phase;
    final label = switch (phase) {
      TimerPhase.idle =>
        duration == null ? 'No timer' : '${(duration / 60).round()} min',
      TimerPhase.running => _countdown(timer.remaining),
      TimerPhase.done => 'Done',
      TimerPhase.overrun => 'Over',
    };
    final copy = switch (phase) {
      TimerPhase.idle =>
        duration == null
            ? 'This step has no timer.'
            : 'Start timer — ${(duration / 60).round()} min. Tap the ring.',
      TimerPhase.running => '${_countdown(timer.remaining)} left',
      TimerPhase.done => 'Timer done. Clear it when you are ready.',
      TimerPhase.overrun =>
        'Timer finished '
            '${_ago(timer.overdue ?? Duration.zero)} ago.',
    };
    final onTap = duration == null
        ? null
        : phase == TimerPhase.idle
        ? controller.startTimer
        : controller.clearTimer;

    return PixelPanel(
      tone: phase == TimerPhase.running
          ? PixelPanelTone.inset
          : PixelPanelTone.raised,
      child: Row(
        children: <Widget>[
          PixelTimerRing(
            state: switch (phase) {
              TimerPhase.idle => PixelTimerState.idle,
              TimerPhase.running => PixelTimerState.running,
              TimerPhase.done => PixelTimerState.done,
              TimerPhase.overrun => PixelTimerState.overrun,
            },
            label: label,
            progress: phase == TimerPhase.running && duration != null
                ? timer.remaining.inSeconds / duration
                : 0,
            onTap: onTap,
            semanticLabel: 'Timer, $copy',
          ),
          SizedBox(width: unit * 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('TIMER', style: PixelType.sectionLabel),
                SizedBox(height: unit),
                Text(copy, style: PixelType.bodySmall),
                if (phase != TimerPhase.idle) ...<Widget>[
                  SizedBox(height: unit),
                  Text(
                    phase == TimerPhase.idle ? '' : 'Clear timer',
                    style: PixelType.meta,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _countdown(Duration remaining) {
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final minutes = safe.inMinutes.toString().padLeft(2, '0');
    final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _ago(Duration ago) {
    if (ago < const Duration(minutes: 1)) {
      return 'less than a minute';
    }
    return '${ago.inMinutes} min';
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.copy, required this.onDismiss});

  final String copy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return PixelPanel(
      tone: PixelPanelTone.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('WELCOME BACK', style: PixelType.sectionLabel),
          SizedBox(height: unit),
          Text(copy, style: PixelType.bodySmall),
          SizedBox(height: unit * 2),
          PixelFilterChip(label: 'Got it', selected: false, onTap: onDismiss),
        ],
      ),
    );
  }
}

/// The scene strip (`docs/07` §9.1): one background band and at most three
/// sprites above the step card - the step scene, its appliance and the dish.
class _SceneStrip extends StatelessWidget {
  const _SceneStrip({
    required this.stepSpriteKey,
    required this.equipmentCode,
    required this.dishStampKey,
  });

  final String stepSpriteKey;
  final String? equipmentCode;
  final String? dishStampKey;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Semantics(
      label: 'step scene',
      child: ExcludeSemantics(
        child: PixelPanel(
          tone: PixelPanelTone.inset,
          padding: EdgeInsets.symmetric(
            horizontal: unit * 3,
            vertical: unit * 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              PixelSprite(spriteKey: stepSpriteKey, artUnits: 18),
              if (equipmentCode != null)
                PixelSprite(spriteKey: 'eq_$equipmentCode', artUnits: 14),
              if (dishStampKey != null)
                PixelSprite(spriteKey: dishStampKey!, artUnits: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideAnywayBanner extends StatelessWidget {
  const _GuideAnywayBanner({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return PixelPanel(
      tone: PixelPanelTone.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('STARTED ANYWAY', style: PixelType.sectionLabel),
          SizedBox(height: unit),
          Text(
            codes.isEmpty
                ? 'This cook started with no missing requirements.'
                : 'This cook started with these missing: '
                      '${_humanize(codes)}.',
            style: PixelType.bodySmall.copyWith(color: PixelPalette.rustDark),
          ),
          if (codes.isNotEmpty) ...<Widget>[
            SizedBox(height: unit),
            Text('recorded: ${codes.join(', ')}', style: PixelType.meta),
          ],
        ],
      ),
    );
  }

  static String _humanize(List<String> codes) {
    return codes
        .map(
          (code) => code
              .replaceFirst('equipment:', '')
              .replaceFirst('ingredient:', '')
              .replaceFirst('group:', '')
              .replaceAll('_', ' '),
        )
        .join(', ');
  }
}

class _LeaveDialog extends StatelessWidget {
  const _LeaveDialog({required this.recipeName});

  final String recipeName;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Dialog(
      backgroundColor: const Color(0x00000000),
      insetPadding: EdgeInsets.all(unit * 6),
      child: PixelPanel(
        tone: PixelPanelTone.dark,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'LEAVE THIS COOK?',
              style: PixelType.chromeMeta.copyWith(
                fontSize: 16,
                color: PixelPalette.banig,
              ),
            ),
            SizedBox(height: unit * 2),
            Text(
              'Leaving keeps $recipeName in progress. Abandoning '
              'writes no stock changes.',
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
                color: PixelPalette.cream,
              ),
            ),
            SizedBox(height: unit * 3),
            PixelButton(
              label: 'Keep cooking',
              kind: PixelButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: unit * 2),
            PixelButton(
              label: 'Leave for now',
              onPressed: () => Navigator.of(context).pop('leave'),
            ),
            SizedBox(height: unit * 2),
            PixelButton(
              label: 'Abandon cook',
              kind: PixelButtonKind.destructive,
              onPressed: () => Navigator.of(context).pop('abandon'),
            ),
          ],
        ),
      ),
    );
  }
}
