/// Pixel screen scaffolding: the art canvas, safe areas and the standard
/// app-bar/body/footer column (`docs/07` §1.4).
library;

import 'package:flutter/material.dart';

import 'pixel_app_bar.dart';
import 'pixel_canvas.dart';
import 'pixel_theme.dart';

/// A page as the app shows it: cream canvas, safe areas, optional bottom bar
/// (the tab shell supplies one for root screens).
class PixelScreenScaffold extends StatelessWidget {
  const PixelScreenScaffold({
    super.key,
    required this.child,
    this.bottomNavigationBar,
  });

  final Widget child;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelPalette.cream,
      body: PixelCanvas(child: SafeArea(child: child)),
      bottomNavigationBar: bottomNavigationBar == null
          ? null
          : ColoredBox(
              color: PixelPalette.cream,
              child: SafeArea(top: false, child: bottomNavigationBar!),
            ),
    );
  }
}

/// App bar + optional section header + scrollable body + pinned footer.
class PixelPage extends StatelessWidget {
  const PixelPage({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.onSettings,
    this.trailing,
    this.header,
    this.footer,
    this.bodyPadding,
  });

  final String title;
  final Widget body;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final Widget? trailing;
  final Widget? header;
  final Widget? footer;
  final EdgeInsets? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final unit = PixelScaleProvider.of(context).au(1);
    final horizontal = unit * PixelSpacing.contentMarginAu;
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: PixelAppBar(
            title: title,
            onBack: onBack,
            onSettings: onSettings,
            trailing: trailing,
          ),
        ),
        if (header != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: header!,
          ),
        Expanded(
          child: Padding(
            padding:
                bodyPadding ?? EdgeInsets.symmetric(horizontal: horizontal),
            child: body,
          ),
        ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: Padding(
              padding: EdgeInsets.only(bottom: unit * 3, top: unit * 2),
              child: footer!,
            ),
          ),
      ],
    );
  }
}
