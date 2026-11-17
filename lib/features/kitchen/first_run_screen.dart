/// First run / kitchen setup (`docs/07` §7 screen 1): the one local profile —
/// name, equipment and the privacy note. Equipment may be empty: that only
/// makes equipment-dependent dishes blocked, never hidden.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../ui/pixel/pixel_button.dart';
import '../../ui/pixel/pixel_canvas.dart';
import '../../ui/pixel/pixel_panel.dart';
import '../../ui/pixel/pixel_scaffold.dart';
import '../../ui/pixel/pixel_theme.dart';
import 'equipment_picker_sheet.dart';

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key});

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final TextEditingController _name = TextEditingController(text: 'My Kitchen');
  String? _error;

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
        return PixelScreenScaffold(
          child: PixelPage(
            title: 'KUSINA',
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('WELCOME', style: PixelType.heading),
                SizedBox(height: unit),
                Text(
                  'One kitchen, kept on this phone.',
                  style: PixelType.bodySmall,
                ),
                SizedBox(height: unit * 3),
              ],
            ),
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
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_error != null) ...<Widget>[
                  SizedBox(height: unit),
                  Text(
                    _error!,
                    style: PixelType.meta.copyWith(
                      color: PixelPalette.rustDark,
                    ),
                  ),
                ],
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
                Text('This stays on this phone.', style: PixelType.meta),
              ],
            ),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PixelButton(label: 'Start cooking', onPressed: () => _save()),
                SizedBox(height: unit * 2),
                PixelButton(
                  label: 'Skip',
                  kind: PixelButtonKind.secondary,
                  onPressed: _markConfiguredAndGoHome,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the kitchen a name to continue.');
      return;
    }
    await AppScope.of(context).kitchen.rename(name);
    if (mounted) {
      _markConfiguredAndGoHome();
    }
  }

  /// Setup is the only screen that can flip the routing flag. Write it before
  /// navigating: the router's redirect reads this value, so without it both
  /// Start and Skip land back on `/setup` (the flag is captured at app start).
  void _markConfiguredAndGoHome() {
    AppScope.of(context).repositories.kitchenConfigured = true;
    context.go('/');
  }
}
