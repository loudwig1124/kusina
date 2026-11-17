/// Inventory: one row per ingredient with a 2 x 2 grid of status chips. One tap
/// writes one stock event; there is no numeric input anywhere (`docs/07` §7
/// screen 7, §5.3).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../domain/models/stock.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.stock,
      builder: (context, _) {
        final unit = PixelScaleProvider.of(context).au(1);
        final stock = scope.stock;
        final all = stock.ingredients;
        final categories =
            all.map((ingredient) => ingredient.category).toSet().toList()
              ..sort();
        final visible = all
            .where((ingredient) {
              final matchesQuery =
                  _query.isEmpty ||
                  ingredient.name.toLowerCase().contains(_query) ||
                  ingredient.filipinoGloss.toLowerCase().contains(_query);
              final matchesCategory =
                  _category == null || ingredient.category == _category;
              return matchesQuery && matchesCategory;
            })
            .toList(growable: false);

        return PixelPage(
          title: 'INVENTORY',
          onSettings: () => context.push('/settings'),
          trailing: Padding(
            padding: EdgeInsets.only(right: unit * 2),
            child: Text('${all.length} ITEMS', style: PixelType.chromeMeta),
          ),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PixelPanel(
                tone: PixelPanelTone.inset,
                padding: EdgeInsets.symmetric(
                  horizontal: unit * 3,
                  vertical: unit,
                ),
                child: Row(
                  children: <Widget>[
                    Text('⌕', style: PixelType.statusLabel),
                    SizedBox(width: unit * 2),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                        style: PixelType.rowLabel,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search ingredients',
                          hintStyle: PixelType.meta,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: unit * 2),
              Wrap(
                spacing: unit * 2,
                runSpacing: unit * 2,
                children: <Widget>[
                  PixelFilterChip(
                    label: 'All',
                    selected: _category == null,
                    onTap: () => setState(() => _category = null),
                  ),
                  for (final category in categories)
                    PixelFilterChip(
                      label: _categoryLabel(category),
                      selected: _category == category,
                      onTap: () => setState(() => _category = category),
                    ),
                ],
              ),
              SizedBox(height: unit * 3),
            ],
          ),
          body: stock.isLoading
              ? const Center(
                  child: Text('Loading stock…', style: PixelType.meta),
                )
              : visible.isEmpty
              ? Center(
                  child: Text(
                    'No ingredient matches.',
                    style: PixelType.bodySmall,
                  ),
                )
              : PixelPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text('INGREDIENTS', style: PixelType.sectionLabel),
                          const Spacer(),
                          Text(
                            '${visible.length} OF ${all.length}',
                            style: PixelType.chromeMeta,
                          ),
                        ],
                      ),
                      SizedBox(height: unit * 2),
                      Expanded(
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (context, index) =>
                              SizedBox(height: unit * 3),
                          itemBuilder: (context, index) {
                            final ingredient = visible[index];
                            return _StockRow(
                              key: ValueKey<String>(
                                'stock-row-${ingredient.code}',
                              ),
                              ingredientCode: ingredient.code,
                              label: ingredient.label,
                              status: stock.statusFor(ingredient.code),
                              onPick: (status) =>
                                  _write(ingredient.code, status),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _write(String ingredientCode, StockStatus status) async {
    final stock = AppScope.of(context).stock;
    final written = await stock.setStatus(ingredientCode, status);
    if (!mounted || !written) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          backgroundColor: PixelPalette.adobo,
          content: Text(
            'Saved. No numbers to type.',
            style: TextStyle(color: PixelPalette.cream, fontSize: 16),
          ),
          duration: Duration(seconds: 2),
        ),
      );
  }

  static String _categoryLabel(String category) {
    final words = category.split('_');
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}

/// One ingredient block: label above the 2 x 2 chip grid.
class _StockRow extends StatelessWidget {
  const _StockRow({
    super.key,
    required this.ingredientCode,
    required this.label,
    required this.status,
    required this.onPick,
  });

  final String ingredientCode;
  final String label;
  final StockStatus status;
  final ValueChanged<StockStatus> onPick;

  static const List<List<StockStatus>> _grid = <List<StockStatus>>[
    <StockStatus>[StockStatus.have, StockStatus.low],
    <StockStatus>[StockStatus.out, StockStatus.unknown],
  ];

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: PixelType.rowLabel),
        SizedBox(height: unit * 2),
        for (final row in _grid) ...<Widget>[
          Row(
            children: <Widget>[
              for (var index = 0; index < row.length; index++) ...<Widget>[
                if (index > 0) SizedBox(width: unit * 2),
                Expanded(
                  child: PixelStatusChip(
                    key: ValueKey<String>(
                      'stock-chip-$ingredientCode-${row[index].wireCode}',
                    ),
                    status: row[index],
                    selected: row[index] == status,
                    onTap: () => onPick(row[index]),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: unit * 2),
        ],
      ],
    );
  }
}
