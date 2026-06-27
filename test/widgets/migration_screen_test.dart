import 'package:bonken/screens/export_screen.dart';
import 'package:bonken/screens/migration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// Mocks the `url_launcher` platform channel so the Play Store launch can be
/// exercised without a real platform. Returns the list of launched URLs;
/// [result] is what the platform reports (true = handled, false = no handler).
List<String> _mockUrlLauncher(WidgetTester tester, {required bool result}) {
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    switch (call.method) {
      case 'canLaunch':
        return true;
      case 'launch':
      case 'launchUrl':
        launched.add((call.arguments as Map)['url'] as String);
        return result;
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return launched;
}

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

  testWidgets('the heading is a semantics header', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MigrationScreen())),
    );
    await tester.pumpAndSettle();
    final heading = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Bonken is verhuisd'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(heading.properties.header, isTrue);
  });

  testWidgets('content scrolls (no overflow) at a large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(3)),
            child: MigrationScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // The recovery actions are still reachable inside the scroll view.
    expect(find.text('Installeer de nieuwe app'), findsOneWidget);
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

  testWidgets(
    '"Exporteer gegevens" stays disabled when the game history is corrupt',
    (tester) async {
      // Export reads the raw stored blob, so a corrupt/unreadable history must
      // NOT be exportable — we never hand the user a backup the new app would
      // reject. (A corrupt history shouldn't occur here in the first place: the
      // legacy app reads its own data.)
      setAsyncPrefs({'bonken_game_history': 'this is not json'});

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MigrationScreen())),
      );
      // Let build() settle into AsyncError before the ~200ms Riverpod retry.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final exportButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Exporteer gegevens'),
      );
      expect(exportButton.onPressed, isNull);

      // Drain the retry: clear the bad key so the retried build() returns [].
      final prefs = SharedPreferencesAsync();
      await prefs.remove('bonken_game_history');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('"Exporteer gegevens" opens the export screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MigrationScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Exporteer gegevens'));
    await tester.pumpAndSettle();

    expect(find.byType(ExportScreen), findsOneWidget);
  });

  testWidgets('"Installeer de nieuwe app" launches the Play Store listing', (
    tester,
  ) async {
    final launched = _mockUrlLauncher(tester, result: true);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MigrationScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Installeer de nieuwe app'),
    );
    await tester.pump();
    await tester.pump();

    expect(
      launched.single,
      'https://play.google.com/store/apps/details?id=org.suninet.bonken',
    );
    // The launch succeeded, so no failure snackbar is shown.
    expect(find.text('Kan de Play Store niet openen.'), findsNothing);
  });

  testWidgets(
    'a failed Play Store launch shows the "Kan de Play Store niet openen" snackbar',
    (tester) async {
      _mockUrlLauncher(tester, result: false);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MigrationScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, 'Installeer de nieuwe app'),
      );
      await tester.pump(); // run _openPlayStore through the awaited launchUrl
      await tester.pump(); // let the snackbar insert

      expect(find.text('Kan de Play Store niet openen.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5)); // drain the snackbar timer
    },
  );
}
