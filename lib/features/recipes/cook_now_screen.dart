/// Cook now (`docs/07` §7 screen 2): the resume card when a cook is in progress,
/// then the three dishes with their default-method availability badge.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/guide/guide_models.dart';
import '../../domain/models/recipe.dart';
import '../../domain/rules/availability_service.dart';
import '../../ui/pixel/pixel_availability_presentation.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_sprite.dart';
import '../../ui/pixel/pixel_theme.dart';
import '../guide/app_data_refresh.dart';
import '../guide/guide_controller.dart';
import 'recipes_controller.dart';

class CookNowScreen extends StatefulWidget {
  const CookNowScreen({super.key});

  @override
  State<CookNowScreen> createState() => _CookNowScreenState();
}

class _CookNowScreenState extends State<CookNowScreen> {
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _refreshed) {
        return;
      }
      _refreshed = true;
      // A relaunch on SQLite finds the in-progress cook here.
      await AppScope.of(context).guide.refreshActiveSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        scope.recipes,
        scope.kitchen,
        scope.guide,
      ]),
      builder: (context, _) {
        final unit = PixelScaleProvider.of(context).au(1);
        final recipes = scope.recipes;
        final guide = scope.guide;
        final cards = recipes.cards;
        final active = guide.activeSession;
        final equipmentLine = scope.kitchen.catalog
            .where((item) => scope.kitchen.owns(item.code))
            .map((item) => item.name.toUpperCase())
            .join(' + ');
        return PixelPage(
          title: 'KUSINA',
          onSettings: () => context.push('/settings'),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('COOK NOW', style: PixelType.heading),
              const SizedBox(height: 2),
              Text(
                '${scope.kitchen.kitchenName} | ${cards.length} dishes',
                style: PixelType.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                equipmentLine.isEmpty ? 'NO EQUIPMENT SET' : equipmentLine,
                style: PixelType.chromeMeta,
              ),
              SizedBox(height: unit * 3),
            ],
          ),
          body: recipes.isLoading
              ? const Center(
                  child: Text('Loading dishes…', style: PixelType.meta),
                )
              : recipes.error != null
              ? const Center(
                  child: Text('No dishes seeded', style: PixelType.bodySmall),
                )
              : ListView(
                  padding: EdgeInsets.only(bottom: unit * 4),
                  children: <Widget>[
                    if (active != null) ...<Widget>[
                      _ResumeCard(
                        session: active,
                        methodLabel: guide.methodLabel,
                        timerCopy: _timerCopy(guide),
                        onResume: () => context.push('/guide/${active.id}'),
                        onAbandon: () => _abandon(active),
                      ),
                      SizedBox(height: unit * 4),
                    ],
                    for (
                      var index = 0;
                      index < cards.length;
                      index++
                    ) ...<Widget>[
                      if (index > 0) SizedBox(height: unit * 4),
                      _RecipeCard(
                        card: cards[index],
                        onTap: () => context.push(
                          '/recipes/${cards[index].recipe.slug}',
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  String? _timerCopy(GuideController guide) {
    final timer = guide.timer;
    if (timer.phase == TimerPhase.running) {
      final remaining = timer.remaining;
      final minutes = remaining.inMinutes.toString().padLeft(2, '0');
      final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds left';
    }
    if (timer.phase == TimerPhase.done) {
      return 'Timer done';
    }
    if (timer.phase == TimerPhase.overrun) {
      return 'Timer finished while away';
    }
    return null;
  }

  Future<void> _abandon(GuidedSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0x00000000),
        child: PixelPanel(
          tone: PixelPanelTone.dark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ABANDON THIS COOK?',
                style: PixelType.chromeMeta.copyWith(
                  fontSize: 16,
                  color: PixelPalette.banig,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${session.recipeName} stops at step '
                '${session.currentStepNumber} of ${session.totalSteps}. '
                'No stock changes are written.',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: PixelPalette.cream,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: PixelButton(
                      label: 'Keep cooking',
                      kind: PixelButtonKind.secondary,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PixelButton(
                      label: 'Abandon',
                      kind: PixelButtonKind.destructive,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await AppScope.of(context).guide.abandon();
    if (!mounted) {
      return;
    }
    await refreshAppData(context);
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
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.session,
    required this.methodLabel,
    required this.timerCopy,
    required this.onResume,
    required this.onAbandon,
  });

  final GuidedSession session;
  final String methodLabel;
  final String? timerCopy;
  final VoidCallback onResume;
  final VoidCallback onAbandon;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final stepLabel = session.isReview
        ? 'At the usage review'
        : 'Step ${session.currentStepNumber} of ${session.totalSteps}';
    return Semantics(
      label: 'Resume ${session.recipeName}, $stepLabel',
      child: PixelPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                PixelSprite(spriteKey: 'tab_cook', artUnits: 14),
                SizedBox(width: unit * 2),
                Expanded(
                  child: Text(
                    'COOK IN PROGRESS',
                    style: PixelType.sectionLabel,
                  ),
                ),
              ],
            ),
            SizedBox(height: unit * 2),
            Text(session.recipeName, style: PixelType.stepTitle),
            SizedBox(height: unit),
            Text('$methodLabel · $stepLabel', style: PixelType.bodySmall),
            if (session.startedWithoutAvailability) ...<Widget>[
              SizedBox(height: unit),
              Text(
                'Started anyway: ${session.missingCodes.join(', ')}',
                style: PixelType.meta.copyWith(color: PixelPalette.rustDark),
              ),
            ],
            if (timerCopy != null) ...<Widget>[
              SizedBox(height: unit),
              Text(timerCopy!, style: PixelType.meta),
            ],
            SizedBox(height: unit * 2),
            PixelButton(label: 'Resume', onPressed: onResume),
            SizedBox(height: unit * 2),
            PixelButton(
              label: 'Abandon',
              kind: PixelButtonKind.secondary,
              onPressed: onAbandon,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.card, required this.onTap});

  final RecipeCardData card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final RecipeDetail recipe = card.recipe;
    final AvailabilityResult availability = card.availability;
    return Semantics(
      button: true,
      label:
          '${recipe.name}, ${availability.state.label}, '
          '${recipe.baseServings} servings, ${recipe.totalMinutes} minutes',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PixelPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PixelSprite(spriteKey: recipe.dishStampKey, artUnits: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(recipe.name, style: PixelType.stepTitle),
                    const SizedBox(height: 4),
                    Text(
                      '${recipe.baseServings} servings | '
                      '${recipe.totalMinutes} min',
                      style: PixelType.meta,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PixelAvailabilityBadge(state: availability.state),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
