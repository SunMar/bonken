import 'package:bonken/screens/export_screen.dart';
import 'package:bonken/screens/migration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  setUpPrefs();
  initializeWidgets();

  testWidgets('renders the moved-app message and both actions', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MigrationScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bonken is verhuisd'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Installeer de nieuwe app'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Exporteer gegevens'),
      findsOneWidget,
    );
  });

  testWidgets('"Exporteer gegevens" is disabled until history loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MigrationScreen())),
    );

    OutlinedButton exportButton() => tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Exporteer gegevens'),
    );

    // First frame: game history is still loading → export is disabled so the
    // user cannot push the export flow before its data is ready.
    expect(exportButton().onPressed, isNull);

    await tester.pumpAndSettle();

    // History resolved → export becomes available.
    expect(exportButton().onPressed, isNotNull);
  });

  testWidgets('"Exporteer gegevens" opens the export screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MigrationScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Exporteer gegevens'));
    await tester.pumpAndSettle();

    expect(find.byType(ExportScreen), findsOneWidget);
  });
}
