import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/assertions.dart';
import '../helpers/fixture_harness.dart';

/// `docs/06` §8 #5 / `docs/07` §5.3: the acceptance path has zero numeric
/// inputs. This walks every route so a new screen cannot quietly add one.
void main() {
  const routes = <String>[
    '/setup',
    '/',
    '/recipes',
    '/recipes/chicken-adobo',
    '/recipes/crispy-pork-belly',
    '/guide/preview?slug=chicken-adobo',
    '/guide/preview/review',
    '/stock',
    '/stock/bay_leaf',
    '/history',
    '/settings',
  ];

  for (final route in routes) {
    testWidgets('no numeric input on $route', (tester) async {
      final harness = await createHarness();
      await pumpKusinaApp(
        tester,
        harness,
        initialLocation: route,
        height: 2400,
      );

      expectNoNumericInputs(tester);
    });
  }

  testWidgets('the only text field is the kitchen name, with a text keyboard', (
    tester,
  ) async {
    final harness = await createHarness();
    await pumpKusinaApp(tester, harness, initialLocation: '/settings');

    final fields = find.byType(EditableText);
    expect(fields, findsOneWidget);
    expectNoNumericInputs(tester);
  });
}
