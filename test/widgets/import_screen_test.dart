import 'dart:convert';
import 'dart:typed_data';

import 'package:bonken/models/app_version.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/screens/import_screen.dart';
import 'package:bonken/state/export_import_notifier.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/migrations.dart' show currentStorageVersion;
import 'package:bonken/state/platform_io_providers.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

GameSession _session() {
  final dt = DateTime(2024);
  final players = [
    Player(name: 'A'),
    Player(name: 'B'),
    Player(name: 'C'),
    Player(name: 'D'),
  ];
  return GameSession(
    id: kGameId1,
    createdAt: dt,
    updatedAt: dt,
    scoredAt: dt,
    players: players,
    firstDealerId: players[0].id,
    rounds: const [],
  );
}

final _validSettingsJson = jsonEncode({
  'version': 1,
  'themeMode': 'dark',
  'ruleVariants': {
    'starterVariant': 'dealerStarts',
    'heartsVariant': 'onlyAfterPlayedHeart',
  },
});

Future<Uint8List> _buildZip({
  List<GameSession>? sessions,
  String? settingsJson,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (sessions != null) {
    await prefs.setString(
      GameHistoryNotifier.storageKey,
      jsonEncode({
        'version': currentStorageVersion,
        'games': [for (final s in sessions) s.toJson()],
      }),
    );
  }
  if (settingsJson != null) {
    await prefs.setString(settingsStorageKey, settingsJson);
  }
  return exportBackup(
    prefs: prefs,
    appVersion: const AppVersion(version: '1.0.0', buildNumber: '1'),
    includeGames: sessions != null,
    includeSettings: settingsJson != null,
  );
}

Future<void> _pump(WidgetTester tester, {Future<Uint8List?> Function()? pick}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (pick != null) pickBackupBytesProvider.overrideWithValue(pick),
      ],
      child: const MaterialApp(home: ImportScreen()),
    ),
  );
}

void main() {
  setUpPrefs();
  initializeWidgets();

  testWidgets('renders title "Importeer gegevens"', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Importeer gegevens'), findsOneWidget);
  });

  testWidgets('renders "Kies bestand" button', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Kies bestand'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('renders idle description text', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('backup-bestand'), findsOneWidget);
  });

  testWidgets('valid backup → analyzed state shows stream options', (
    tester,
  ) async {
    final zip = await _buildZip(
      sessions: [_session()],
      settingsJson: _validSettingsJson,
    );
    await _pump(tester, pick: () async => zip);

    await tester.tap(find.widgetWithText(FilledButton, 'Kies bestand'));
    await tester.pumpAndSettle();

    expect(find.text('Spellen (1)'), findsOneWidget);
    expect(find.text('Instellingen'), findsOneWidget);
    // Both streams importable → checkboxes default to checked.
    final games = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Spellen (1)'),
    );
    expect(games.value, isTrue);
    expect(find.widgetWithText(FilledButton, 'Importeer'), findsOneWidget);
  });

  testWidgets('"Importeer" opens the replace-confirmation dialog', (
    tester,
  ) async {
    final zip = await _buildZip(sessions: [_session()]);
    await _pump(tester, pick: () async => zip);

    await tester.tap(find.widgetWithText(FilledButton, 'Kies bestand'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Importeer'));
    await tester.pumpAndSettle();

    expect(find.text('Gegevens vervangen'), findsOneWidget);
  });

  testWidgets('corrupt file → shows error dialog and returns to idle', (
    tester,
  ) async {
    await _pump(tester, pick: () async => Uint8List.fromList([1, 2, 3, 4]));

    await tester.tap(find.widgetWithText(FilledButton, 'Kies bestand'));
    await tester.pumpAndSettle();

    expect(find.text('Importeren mislukt'), findsOneWidget);
  });

  group('partialImportMessage', () {
    test('games committed, settings failed', () {
      final msg = partialImportMessage(
        const PartialImportException(
          gamesImported: 3,
          settingsUpdated: false,
          cause: 'boom',
        ),
        importedGames: true,
        importedSettings: true,
      );
      expect(msg, contains('Hersteld: spellen.'));
      expect(msg, contains('Niet hersteld: instellingen.'));
    });

    test('settings committed, games failed', () {
      final msg = partialImportMessage(
        const PartialImportException(
          gamesImported: 0,
          settingsUpdated: true,
          cause: 'boom',
        ),
        importedGames: true,
        importedSettings: true,
      );
      expect(msg, contains('Hersteld: instellingen.'));
      expect(msg, contains('Niet hersteld: spellen.'));
    });
  });
}
