/// All recipes: the same three states as Cook now plus a filter
/// (`docs/07` §7 screen 3).
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/rules/availability_service.dart';
import '../../ui/pixel/pixel_availability_presentation.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_sprite.dart';
import '../../ui/pixel/pixel_theme.dart';

class AllRecipesScreen extends StatefulWidget {
  const AllRecipesScreen({super.key});

  @override
  State<AllRecipesScreen> createState() => _AllRecipesScreenState();
}

class _AllRecipesScreenState extends State<AllRecipesScreen> {
  AvailabilityState? _filter;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.recipes, scope.kitchen]),
      builder: (context, _) {
        final unit = PixelScaleProvider.of(context).au(1);
        final all = scope.recipes.cards;
        final visible = _filter == null
            ? all
            : all
                  .where((card) => card.availability.state == _filter)
                  .toList(growable: false);
        return PixelPage(
          title: 'RECIPES',
          onSettings: () => context.push('/settings'),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: unit * 2,
                runSpacing: unit * 2,
                children: <Widget>[
                  PixelFilterChip(
                    label: 'All',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final state in AvailabilityState.values)
                    PixelFilterChip(
                      label: state.label,
                      selected: _filter == state,
                      onTap: () => setState(() => _filter = state),
                    ),
                ],
              ),
              SizedBox(height: unit * 3),
            ],
          ),
          body: visible.isEmpty
              ? Center(
                  child: Text(
                    'Nothing matches. Clear filter.',
                    style: PixelType.bodySmall,
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.only(bottom: unit * 4),
                  itemCount: visible.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: unit * 3),
                  itemBuilder: (context, index) {
                    final card = visible[index];
                    return Semantics(
                      button: true,
                      label:
                          '${card.recipe.name}, '
                          '${card.availability.state.label}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            context.push('/recipes/${card.recipe.slug}'),
                        child: PixelPanel(
                          child: Row(
                            children: <Widget>[
                              PixelSprite(
                                spriteKey: card.recipe.dishStampKey,
                                artUnits: 16,
                              ),
                              SizedBox(width: unit * 3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      card.recipe.name,
                                      style: PixelType.rowLabel.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      _equipmentLine(context, card.recipe.slug),
                                      style: PixelType.meta,
                                    ),
                                  ],
                                ),
                              ),
                              PixelAvailabilityBadge(
                                state: card.availability.state,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  String _equipmentLine(BuildContext context, String slug) {
    final recipes = AppScope.of(context).recipes;
    final recipe = recipes.recipeFor(slug);
    if (recipe == null) {
      return '';
    }
    if (recipe.hasMethodChoice) {
      return recipe.methods.map((method) => method.label).join(' / ');
    }
    return recipe.requiredEquipmentCodes.map(recipes.equipmentName).join(' + ');
  }
}
