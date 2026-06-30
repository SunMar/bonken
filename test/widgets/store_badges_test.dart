// Tests for the App Store / Google Play badges shown in the About dialog.
// The dialog itself gates them behind `kIsWeb`, which is false under
// `flutter test`, so the web-only [StoreBadges] widget is pumped directly here
// (the About-dialog test asserts the gate hides it on non-web).

import 'package:bonken/widgets/app_bar_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpBadges(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: Center(child: StoreBadges())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders both store badges from the bundled NL artwork', (
    tester,
  ) async {
    await _pumpBadges(tester);

    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as AssetImage).assetName)
        .toList();
    expect(assetNames, hasLength(2));
    expect(
      assetNames,
      containsAll(<String>[
        'assets/store/app_store_badge_nl.png',
        'assets/store/google_play_badge_nl.png',
      ]),
    );
  });

  testWidgets('each badge is a labelled, tappable, 48dp-tall target', (
    tester,
  ) async {
    await _pumpBadges(tester);

    // Screen-reader labels (the artwork carries no machine-readable text).
    expect(find.bySemanticsLabel('Download in de App Store'), findsOneWidget);
    expect(find.bySemanticsLabel('Ontdek het op Google Play'), findsOneWidget);

    final inkWells = find.byType(InkWell);
    expect(inkWells, findsNWidgets(2));
    for (final inkWell in tester.widgetList<InkWell>(inkWells)) {
      expect(inkWell.onTap, isNotNull);
    }
    // Both tap targets meet the 48dp accessibility minimum.
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(inkWells.at(i)).height, greaterThanOrEqualTo(48));
    }
  });
}
