/// Recipe detail: method control with per-method badges, the availability
/// panel, the ingredient list and the single start action (`docs/07` §7 screen 4
/// and §7.1).
///
/// The method is never preselected: the primary action stays disabled with
/// "Choose Pan-fry or Air-fry" until the cook taps one, and every panel, warning
/// and label follows that tap.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/guide/guide_models.dart';
import '../../domain/models/recipe.dart';
import '../../domain/models/stock.dart';
import '../../domain/rules/availability_service.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_method_control.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_sprite.dart';
import '../../ui/pixel/pixel_theme.dart';
import 'availability_copy.dart';
import 'recipe_detail_controller.dart';
import 'recipes_controller.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  /// The cook's pick. Kept here so the screen can rebuild the availability
  /// snapshot from the latest environment on every frame; there is no default.
  String? _selectedMethodKey;

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final recipes = scope.recipes;
    final guide = scope.guide;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[recipes, guide]),
      builder: (context, _) {
        final recipe = recipes.recipeFor(widget.slug);
        if (recipe == null) {
          return PixelScreenScaffold(
            child: PixelPage(
              title: 'RECIPE',
              onBack: _close,
              body: Center(
                child: Text(
                  recipes.isLoading
                      ? 'Loading the dish…'
                      : 'That dish is not seeded.',
                  style: PixelType.bodySmall,
                ),
              ),
            ),
          );
        }
        final controller = RecipeDetailController(
          recipe: recipe,
          availabilityService: scope.repositories.availability,
          ownedEquipmentCodes: recipes.ownedEquipmentCodes,
          statuses: recipes.statuses,
          selectedMethodKey: _selectedMethodKey,
        );
        return _buildDetail(context, recipes, controller, guide.activeSession);
      },
    );
  }

  Widget _buildDetail(
    BuildContext context,
    RecipesController recipes,
    RecipeDetailController controller,
    GuidedSession? active,
  ) {
    final recipe = controller.recipe;
    final unit = PixelScaleProvider.of(context).au(1);
    final availability = controller.selectedAvailability;
    final missingLines = availability == null
        ? const <String>[]
        : AvailabilityCopy.missingLines(
            availability,
            equipmentName: recipes.equipmentName,
            ingredientName: recipes.ingredientName,
          );

    return PixelScreenScaffold(
      child: PixelPage(
        title: 'RECIPE',
        onBack: _close,
        onSettings: () => context.push('/settings'),
        body: ListView(
          padding: EdgeInsets.only(bottom: unit * 4),
          children: <Widget>[
            _Hero(recipe: recipe),
            SizedBox(height: unit * 4),
            if (active != null) ...<Widget>[
              PixelPanel(
                tone: PixelPanelTone.inset,
                child: Text(
                  'A cook is in progress: ${active.recipeName} · '
                  'step ${active.isReview ? active.totalSteps : active.currentStepNumber} '
                  'of ${active.totalSteps}. Finish or abandon it before '
                  'starting another.',
                  style: PixelType.bodySmall,
                ),
              ),
              SizedBox(height: unit * 4),
            ],
            if (recipe.hasMethodChoice) ...<Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      'COOKING METHOD',
                      style: PixelType.sectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Text('NO DEFAULT', style: PixelType.chromeMeta),
                ],
              ),
              SizedBox(height: unit * 2),
              PixelMethodControl(
                selectedKey: controller.selectedMethodKey,
                options: <PixelMethodOption>[
                  for (final method in recipe.methods)
                    PixelMethodOption(
                      key: method.key,
                      label: method.label,
                      iconKey: method.iconKey,
                      availability: controller
                          .availabilityFor(method.key)
                          ?.state,
                      // A pinned session owns the method: no re-pick.
                      isDisabled: active != null,
                    ),
                ],
                onSelected: active != null
                    ? (_) {}
                    : (key) => setState(() => _selectedMethodKey = key),
              ),
              SizedBox(height: unit * 3),
            ],
            _AvailabilityPanel(
              controller: controller,
              availability: availability,
              missingLines: missingLines,
              equipmentName: recipes.equipmentName,
              ingredientName: recipes.ingredientName,
            ),
            SizedBox(height: unit * 3),
            _IngredientsPanel(
              recipe: recipe,
              statusFor: (code) =>
                  recipes.statuses[code] ?? StockStatus.unknown,
            ),
          ],
        ),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PixelButton(
              label: active != null ? 'Resume cook' : controller.primaryLabel,
              onPressed: active != null
                  ? () => context.push('/guide/${active.id}')
                  : controller.canStart
                  ? () => _start(controller, missingLines)
                  : null,
            ),
            if (availability != null) ...<Widget>[
              SizedBox(height: unit * 2),
              Text(switch (availability.state) {
                AvailabilityState.ready =>
                  'Starts on the ${_methodLabel(recipe, controller.selectedMethodKey)} method.',
                AvailabilityState.needsConfirmation =>
                  'Confirm the items above; it still starts.',
                AvailabilityState.blocked =>
                  'Starts anyway and records: ${missingLines.join(' ')}',
              }, style: PixelType.meta),
            ],
          ],
        ),
      ),
    );
  }

  static String _methodLabel(RecipeDetail recipe, String? methodKey) {
    for (final method in recipe.methods) {
      if (method.key == methodKey) {
        return method.label;
      }
    }
    return 'single';
  }

  Future<void> _start(
    RecipeDetailController controller,
    List<String> missingLines,
  ) async {
    final recipe = controller.recipe;
    final methodKey = controller.selectedMethodKey;
    final availability = controller.selectedAvailability;
    if (availability == null) {
      return;
    }
    if (availability.state == AvailabilityState.blocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _GuideAnywayDialog(
          recipeName: recipe.name,
          missingLines: missingLines,
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    final query = <String, String>{
      'slug': recipe.slug,
      'method': ?methodKey,
      if (availability.missingCodes.isNotEmpty)
        'missing': availability.missingCodes.join(','),
    };
    final uri = Uri(path: '/guide/preview', queryParameters: query);
    if (!mounted) {
      return;
    }
    context.push(uri.toString());
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PixelSprite(spriteKey: recipe.dishStampKey, artUnits: 34),
        SizedBox(width: unit * 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(recipe.name, style: PixelType.stepTitle),
              SizedBox(height: unit * 2),
              Text(recipe.servingsLabel, style: PixelType.bodySmall),
              SizedBox(height: unit),
              Text(
                recipe.hasMethodChoice
                    ? '${recipe.methods.length} cooking methods | '
                          '${recipe.totalMinutes} min'
                    : '${recipe.totalMinutes} min | ${recipe.difficulty}',
                style: PixelType.meta,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvailabilityPanel extends StatelessWidget {
  const _AvailabilityPanel({
    required this.controller,
    required this.availability,
    required this.missingLines,
    required this.equipmentName,
    required this.ingredientName,
  });

  final RecipeDetailController controller;
  final AvailabilityResult? availability;
  final List<String> missingLines;
  final String Function(String code) equipmentName;
  final String Function(String code) ingredientName;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final result = availability;
    if (result == null) {
      return PixelPanel(
        tone: PixelPanelTone.inset,
        child: Text(
          'Choose ${controller.recipe.methods.map((method) => method.label).join(' or ')} '
          'to see what you need.',
          style: PixelType.bodySmall,
        ),
      );
    }
    final confirmLine = AvailabilityCopy.confirmLine(
      result,
      ingredientName: ingredientName,
    );
    final lowLine = AvailabilityCopy.lowLine(
      result,
      ingredientName: ingredientName,
    );
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PixelAvailabilityBadge(state: result.state),
              SizedBox(width: unit * 2),
              Expanded(
                child: Text(
                  AvailabilityCopy.headline(result),
                  style: PixelType.bodySmall,
                ),
              ),
            ],
          ),
          if (result.missing.isNotEmpty) ...<Widget>[
            SizedBox(height: unit * 2),
            Text(
              AvailabilityCopy.missingCountLabel(result),
              style: PixelType.chromeMeta,
            ),
            SizedBox(height: unit),
            for (final line in missingLines)
              Padding(
                padding: EdgeInsets.only(top: unit),
                child: Text(
                  line,
                  style: PixelType.meta.copyWith(color: PixelPalette.rustDark),
                ),
              ),
          ],
          if (confirmLine != null) ...<Widget>[
            SizedBox(height: unit * 2),
            Text(
              confirmLine,
              style: PixelType.meta.copyWith(color: PixelPalette.amberDark),
            ),
          ],
          if (lowLine != null) ...<Widget>[
            SizedBox(height: unit * 2),
            Text(
              lowLine,
              style: PixelType.meta.copyWith(color: PixelPalette.amberDark),
            ),
          ],
        ],
      ),
    );
  }
}

class _IngredientsPanel extends StatelessWidget {
  const _IngredientsPanel({required this.recipe, required this.statusFor});

  final RecipeDetail recipe;
  final StockStatus Function(String ingredientCode) statusFor;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final optional = recipe.optionalLines;
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('WHAT YOU NEED', style: PixelType.sectionLabel),
            ],
          ),
          SizedBox(height: unit * 2),
          for (final line in recipe.requiredLines)
            Padding(
              padding: EdgeInsets.only(bottom: unit * 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(line.name, style: PixelType.rowLabel),
                        Text(line.quantityLabel, style: PixelType.meta),
                      ],
                    ),
                  ),
                  PixelStatusChip(
                    status: statusFor(line.ingredientCode),
                    compact: true,
                  ),
                ],
              ),
            ),
          if (optional.isNotEmpty) ...<Widget>[
            Container(height: unit, color: PixelPalette.creamDark),
            SizedBox(height: unit * 2),
            Text(_optionalSummary(optional), style: PixelType.meta),
          ],
        ],
      ),
    );
  }

  static String _optionalSummary(List<RecipeLine> optional) {
    final names = optional
        .take(2)
        .map((line) => line.name.toLowerCase())
        .toList();
    final extra = optional.length - names.length;
    final suffix = extra > 0 ? ', + $extra more' : '';
    return 'Optional (${optional.length}): ${names.join(', ')}$suffix';
  }
}

class _GuideAnywayDialog extends StatelessWidget {
  const _GuideAnywayDialog({
    required this.recipeName,
    required this.missingLines,
  });

  final String recipeName;
  final List<String> missingLines;

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
              'START ANYWAY?',
              style: PixelType.chromeMeta.copyWith(
                fontSize: 16,
                color: PixelPalette.banig,
              ),
            ),
            SizedBox(height: unit * 2),
            Text(
              '$recipeName will start without:',
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
                color: PixelPalette.cream,
              ),
            ),
            SizedBox(height: unit * 2),
            for (final line in missingLines)
              Padding(
                padding: EdgeInsets.only(top: unit),
                child: Text(
                  '• $line',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    color: PixelPalette.cream,
                  ),
                ),
              ),
            SizedBox(height: unit * 3),
            Row(
              children: <Widget>[
                Expanded(
                  child: PixelButton(
                    label: 'Cancel',
                    kind: PixelButtonKind.secondary,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                SizedBox(width: unit * 3),
                Expanded(
                  child: PixelButton(
                    label: 'Guide me anyway',
                    kind: PixelButtonKind.destructive,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
