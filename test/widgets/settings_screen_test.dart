import 'dart:convert';

import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/screens/export_screen.dart';
import 'package:bonken/screens/import_screen.dart';
import 'package:bonken/screens/settings_screen.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: SettingsScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpPrefs();
  initializeWidgets();

  testWidgets('shows section titles for both variant categories', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Uitkomst'), findsOneWidget);
    expect(find.text('Extra spelregel HH/HP'), findsOneWidget);
  });

  testWidgets('shows radio labels for all StarterVariant values', (
    tester,
  ) async {
    await _pump(tester);
    for (final v in StarterVariant.values) {
      expect(find.text(v.label), findsOneWidget);
    }
  });

  testWidgets('shows radio labels for all HeartsVariant values', (
    tester,
  ) async {
    await _pump(tester);
    for (final v in HeartsVariant.values) {
      expect(find.text(v.label), findsOneWidget);
    }
  });

  testWidgets('tapping StarterVariant radio updates provider and persists', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Default is dealerStarts; tap the other option.
    await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
    await tester.pumpAndSettle();

    expect(
      container.read(defaultStarterVariantProvider),
      StarterVariant.oppositeChooserStarts,
    );
    final prefs = SharedPreferencesAsync();
    final blob =
        jsonDecode((await prefs.getString(settingsStorageKey))!)
            as Map<String, dynamic>;
    expect(
      (blob['ruleVariants'] as Map)['starterVariant'],
      'oppositeChooserStarts',
    );
  });

  testWidgets('shows "Gegevens" section with export and import tiles', (
    tester,
  ) async {
    await _pump(tester);
    await tester.scrollUntilVisible(find.text('Gegevens'), 100);
    expect(find.text('Gegevens'), findsOneWidget);
    expect(find.text('Exporteer gegevens'), findsOneWidget);
    expect(find.text('Importeer gegevens'), findsOneWidget);
  });

  testWidgets('export tile navigates to ExportScreen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    await tester.tap(find.text('Exporteer gegevens'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportScreen), findsOneWidget);
  });

  testWidgets('import tile navigates to ImportScreen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    await tester.tap(find.text('Importeer gegevens'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);
  });

  testWidgets('tapping HeartsVariant radio updates provider and persists', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(HeartsVariant.graduatedUnlock.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(HeartsVariant.graduatedUnlock.label));
    await tester.pumpAndSettle();

    expect(
      container.read(defaultHeartsVariantProvider),
      HeartsVariant.graduatedUnlock,
    );
    final prefs = SharedPreferencesAsync();
    final blob =
        jsonDecode((await prefs.getString(settingsStorageKey))!)
            as Map<String, dynamic>;
    expect((blob['ruleVariants'] as Map)['heartsVariant'], 'graduatedUnlock');
  });
}
