/// Equipment picker modal (`docs/07` §7 M1). Not an eleventh screen: it is
/// reached from First run and Settings, and dismiss keeps the previous choice.
library;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../kitchen/kitchen_controller.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_chip.dart';
import '../../ui/pixel/pixel_sprite.dart';
import '../../ui/pixel/pixel_theme.dart';

Future<void> showEquipmentPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PixelPalette.cream,
    isScrollControlled: true,
    builder: (sheetContext) => const _EquipmentPickerSheet(),
  );
}

class _EquipmentPickerSheet extends StatelessWidget {
  const _EquipmentPickerSheet();

  @override
  Widget build(BuildContext context) {
    final kitchen = AppScope.of(context).kitchen;
    final unit = PixelScaleProvider.of(context).au(1);
    return SafeArea(
      child: ListenableBuilder(
        listenable: kitchen,
        builder: (context, _) => Padding(
          padding: EdgeInsets.all(unit * 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('EQUIPMENT', style: PixelType.sectionLabel),
              SizedBox(height: unit * 2),
              Text(
                'Tap what your kitchen has. Unused appliances still appear '
                'here.',
                style: PixelType.meta,
              ),
              SizedBox(height: unit * 3),
              for (final item in kitchen.catalog)
                Padding(
                  padding: EdgeInsets.only(bottom: unit * 2),
                  child: EquipmentToggleRow(
                    key: ValueKey<String>('equipment-${item.code}'),
                    name: item.name,
                    description: item.description,
                    spriteKey: item.spriteKey,
                    owned: kitchen.owns(item.code),
                    note: item.pickerNote,
                    onToggle: () => kitchen.setEquipmentOwned(
                      item.code,
                      owned: !kitchen.owns(item.code),
                    ),
                  ),
                ),
              SizedBox(height: unit * 2),
              PixelButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One appliance row: sprite, name, optional "no dishes yet" note and a 48 dp
/// Owned / Not owned target.
class EquipmentToggleRow extends StatelessWidget {
  const EquipmentToggleRow({
    super.key,
    required this.name,
    required this.description,
    required this.spriteKey,
    required this.owned,
    required this.onToggle,
    this.note,
  });

  final String name;
  final String description;
  final String spriteKey;
  final bool owned;
  final String? note;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    return Row(
      children: <Widget>[
        PixelSprite(spriteKey: spriteKey, artUnits: 14),
        SizedBox(width: unit * 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(name, style: PixelType.rowLabel),
              Text(
                note ?? description,
                style: PixelType.meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        SizedBox(width: unit * 2),
        PixelFilterChip(
          label: owned ? 'Owned' : 'Not owned',
          selected: owned,
          onTap: onToggle,
        ),
      ],
    );
  }
}

/// The kitchen controller is read through [AppScope]; this helper keeps the
/// sheet's imports honest for tests that build it directly.
KitchenController kitchenOf(BuildContext context) =>
    AppScope.of(context).kitchen;
