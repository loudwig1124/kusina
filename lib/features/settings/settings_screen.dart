/// Settings (`docs/07` §7 screen 10): kitchen name, equipment, the safety note,
/// the one destructive action and the version line.
///
/// Reset is blocked while a cook is in progress once sessions exist; Phase A has
/// no sessions, so the guard is the single `hasActiveSession` parameter.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_theme.dart';
import '../kitchen/equipment_picker_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.hasActiveSession = false});

  /// True while a guided cook is in progress; the guide phase supplies it.
  final bool hasActiveSession;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _name = TextEditingController();
  bool _nameSeeded = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nameSeeded) {
      _name.text = AppScope.of(context).kitchen.kitchenName;
      _nameSeeded = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final unit = PixelScaleProvider.of(context).au(1);
    return ListenableBuilder(
      listenable: scope.kitchen,
      builder: (context, _) {
        final kitchen = scope.kitchen;
        if (!_nameSeeded && !kitchen.isLoading) {
          _name.text = kitchen.kitchenName;
          _nameSeeded = true;
        }
        return PixelScreenScaffold(
          child: PixelPage(
            title: 'SETTINGS',
            onBack: context.canPop()
                ? () => context.pop()
                : () => context.go('/'),
            body: ListView(
              children: <Widget>[
                Text('KITCHEN NAME', style: PixelType.sectionLabel),
                SizedBox(height: unit * 2),
                PixelPanel(
                  tone: PixelPanelTone.inset,
                  padding: EdgeInsets.symmetric(
                    horizontal: unit * 3,
                    vertical: unit,
                  ),
                  child: TextField(
                    controller: _name,
                    style: PixelType.rowLabel,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SizedBox(height: unit * 2),
                PixelButton(
                  label: 'Save name',
                  kind: PixelButtonKind.secondary,
                  onPressed: _busy ? null : _saveName,
                ),
                SizedBox(height: unit * 3),
                Text('EQUIPMENT', style: PixelType.sectionLabel),
                SizedBox(height: unit * 2),
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
                  label: 'Edit equipment',
                  kind: PixelButtonKind.secondary,
                  onPressed: () => showEquipmentPicker(context),
                ),
                SizedBox(height: unit * 2),
                Text('This stays on this phone.', style: PixelType.meta),
                SizedBox(height: unit * 4),
                Text('DEMO DATA', style: PixelType.sectionLabel),
                SizedBox(height: unit * 2),
                PixelButton(
                  label: widget.hasActiveSession
                      ? 'Finish or abandon the cook first'
                      : 'Reset demo data',
                  kind: PixelButtonKind.destructive,
                  onPressed: widget.hasActiveSession || _busy ? null : _reset,
                ),
                SizedBox(height: unit * 2),
                Text(
                  'Reset restores the demo kitchen, stock and equipment.',
                  style: PixelType.meta,
                ),
                SizedBox(height: unit * 4),
                Text('Kusina 1.0.0 · SQLite', style: PixelType.meta),
                SizedBox(height: unit * 3),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveName() async {
    final scope = AppScope.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      _name.text = scope.kitchen.kitchenName;
      return;
    }
    setState(() => _busy = true);
    await scope.kitchen.rename(name);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: PixelPalette.adobo,
            content: Text(
              'Saved. This stays on this phone.',
              style: TextStyle(color: PixelPalette.cream, fontSize: 16),
            ),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _reset() async {
    final scope = AppScope.of(context);
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
                'RESET DEMO DATA',
                style: PixelType.chromeMeta.copyWith(
                  fontSize: 16,
                  color: PixelPalette.banig,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This restores the demo kitchen, its equipment and every stock '
                'status. Stock changes you made are lost.',
                style: TextStyle(
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
                      label: 'Cancel',
                      kind: PixelButtonKind.secondary,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PixelButton(
                      label: 'Reset',
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
    setState(() => _busy = true);
    await scope.kitchen.resetDemoData();
    await scope.guide.resetSessions();
    await scope.stock.load();
    await scope.recipes.load();
    await scope.history.load();
    if (mounted) {
      _name.text = AppScope.of(context).kitchen.kitchenName;
      setState(() => _busy = false);
    }
  }
}
