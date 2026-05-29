import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/widgets/variant_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  testWidgets('shows a segment for every enum value', (tester) async {
    StarterVariant? changed;
    await pumpHost(
      tester,
      VariantPicker<StarterVariant>(
        values: StarterVariant.values,
        value: StarterVariant.dealerStarts,
        onChanged: (v) => changed = v,
      ),
    );

    for (final v in StarterVariant.values) {
      expect(find.text(v.label), findsOneWidget);
    }
    expect(changed, isNull); // no tap yet
  });

  testWidgets('tapping a segment fires onChanged with that value', (
    tester,
  ) async {
    StarterVariant? changed;
    await pumpHost(
      tester,
      StatefulBuilder(
        builder: (context, setState) => VariantPicker<StarterVariant>(
          values: StarterVariant.values,
          value: StarterVariant.dealerStarts,
          onChanged: (v) => setState(() => changed = v),
        ),
      ),
    );

    await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
    await tester.pumpAndSettle();

    expect(changed, StarterVariant.oppositeChooserStarts);
  });
}
