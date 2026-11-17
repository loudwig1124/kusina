/// Ingredient detail (P1 shell): current status chips and the append-only event
/// list (`docs/07` §7 screen 8). History is never edited, only appended.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/models/stock.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_theme.dart';

class IngredientDetailScreen extends StatefulWidget {
  const IngredientDetailScreen({super.key, required this.ingredientCode});

  final String ingredientCode;

  @override
  State<IngredientDetailScreen> createState() => _IngredientDetailScreenState();
}

class _IngredientDetailScreenState extends State<IngredientDetailScreen> {
  List<StockEvent> _events = const <StockEvent>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadEvents());
  }

  Future<void> _reloadEvents() async {
    final events = await AppScope.of(context).stock
        .eventsFor(widget.ingredientCode);
    if (mounted) {
      setState(() => _events = events);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final unit = PixelScaleProvider.of(context).au(1);
    return ListenableBuilder(
      listenable: scope.stock,
      builder: (context, _) {
        final ingredient =
            scope.recipes.ingredientFor(widget.ingredientCode) ??
            scope.stock.ingredients
                .where((item) => item.code == widget.ingredientCode)
                .firstOrNull;
        if (ingredient == null) {
          return PixelScreenScaffold(
            child: PixelPage(
              title: 'INGREDIENT',
              onBack: () => context.pop(),
              body: const Center(
                child: Text(
                  'That ingredient is not seeded.',
                  style: PixelType.bodySmall,
                ),
              ),
            ),
          );
        }
        final status = scope.stock.statusFor(ingredient.code);
        return PixelScreenScaffold(
          child: PixelPage(
            title: 'INGREDIENT',
            onBack: () => context.pop(),
            body: ListView(
              children: <Widget>[
                Text(ingredient.name, style: PixelType.stepTitle),
                SizedBox(height: unit),
                Text(ingredient.label, style: PixelType.meta),
                SizedBox(height: unit * 3),
                PixelPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('CURRENT STATUS', style: PixelType.sectionLabel),
                      SizedBox(height: unit * 2),
                      for (final row in const <List<StockStatus>>[
                        <StockStatus>[StockStatus.have, StockStatus.low],
                        <StockStatus>[StockStatus.out, StockStatus.unknown],
                      ])
                        Padding(
                          padding: EdgeInsets.only(bottom: unit * 2),
                          child: Row(
                            children: <Widget>[
                              for (
                                var index = 0;
                                index < row.length;
                                index++
                              ) ...<Widget>[
                                if (index > 0) SizedBox(width: unit * 2),
                                Expanded(
                                  child: PixelStatusChip(
                                    status: row[index],
                                    selected: row[index] == status,
                                    onTap: () async {
                                      await scope.stock.setStatus(
                                        ingredient.code,
                                        row[index],
                                      );
                                      await _reloadEvents();
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: unit * 3),
                PixelPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('CHANGES', style: PixelType.sectionLabel),
                      SizedBox(height: unit * 2),
                      if (_events.isEmpty)
                        Text('No changes yet.', style: PixelType.meta)
                      else
                        for (final event in _events)
                          Padding(
                            padding: EdgeInsets.only(bottom: unit),
                            child: Text(
                              '${event.from.label} → ${event.to.label}'
                              ' · ${event.reason.wireCode}',
                              style: PixelType.rowLabel,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
