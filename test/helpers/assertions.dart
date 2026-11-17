/// Shared widget assertions: the no-numbers rule and the 48 dp floor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `docs/07` rule 3 / §5.3: no numeric input exists on the acceptance path.
void expectNoNumericInputs(WidgetTester tester) {
  for (final editable in tester.widgetList<EditableText>(
    find.byType(EditableText),
  )) {
    expect(
      editable.keyboardType,
      isNot(equals(TextInputType.number)),
      reason: 'no numeric keypad may exist on a cooking screen',
    );
    expect(
      editable.keyboardType,
      isNot(equals(const TextInputType.numberWithOptions(decimal: true))),
    );
    expect(
      editable.keyboardType,
      isNot(equals(const TextInputType.numberWithOptions(signed: true))),
    );
  }
  expect(find.byType(Slider), findsNothing);
  expect(find.byType(Stepper), findsNothing);
}

/// `docs/07` rule 6: every interactive target is at least 48 dp in both
/// dimensions.
void expectMinimumTapTarget(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final size = tester.getSize(find.byWidget(element.widget));
    expect(
      size.width,
      greaterThanOrEqualTo(48),
      reason: 'tap target width for ${element.widget.runtimeType}',
    );
    expect(
      size.height,
      greaterThanOrEqualTo(48),
      reason: 'tap target height for ${element.widget.runtimeType}',
    );
  }
}
