import 'dart:convert';
import 'dart:typed_data';

import 'package:bonken/models/app_version.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/screens/import_screen.dart';
import 'package:bonken/state/backup_codec.dart';
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
  final prefs = SharedPreferencesAsync();
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

Future<void> _pump(
  WidgetTester tester, {
  Future<Uint8List?> Function()? pick,
  ImportNotifier Function()? importNotifier,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Decode inline on the test isolate: the tester's fake-async clock
        // can't drive the production seam's real `Isolate.run`.
        decodeBackupProvider.overrideWithValue(BackupCodec.decode),
        if (pick != null) pickBackupBytesProvider.overrideWithValue(pick),
        if (importNotifier != null)
          importNotifierProvider.overrideWith(importNotifier),
      ],
      child: const MaterialApp(home: ImportScreen()),
    ),
  );
}

/// An [ImportNotifier] whose commit resolves immediately to a fixed success
/// result, so the snackbar-presentation test doesn't depend on real
/// SharedPreferences write latency. The real end-to-end commit is covered in
/// `test/state/export_import_test.dart`.
class _ImmediateImportNotifier extends ImportNotifier {
  @override
  Future<ImportResult> applyImport(
    DecodedBackup backup, {
    required bool importGames,
    required bool importSettings,
  }) async => ImportResult(
    gamesImported: importGames ? 1 : 0,
    settingsUpdated: importSettings,
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
    expect(find.textContaining('backupbestand'), findsOneWidget);
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

  testWidgets('"Importeer" is guarded against re-tap while confirming', (
    tester,
  ) async {
    final zip = await _buildZip(sessions: [_session()]);
    await _pump(tester, pick: () async => zip);

    await tester.tap(find.widgetWithText(FilledButton, 'Kies bestand'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Importeer'));
    await tester.pumpAndSettle();

    // The confirm dialog is open; the underlying button must be disabled so a
    // second tap can't open a second dialog / fire a second commit.
    expect(find.text('Gegevens vervangen'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Importeer'))
          .onPressed,
      isNull,
    );

    // Cancelling releases the guard so the user can retry.
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Importeer'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('confirming import shows success snackbar', (tester) async {
    final zip = await _buildZip(
      sessions: [_session()],
      settingsJson: _validSettingsJson,
    );
    // Stub the commit so this assertion is about snackbar presentation, not
    // real write latency (the _Applying CircularProgressIndicator blocks
    // pumpAndSettle).
    await _pump(
      tester,
      pick: () async => zip,
      importNotifier: _ImmediateImportNotifier.new,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Kies bestand'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Importeer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vervangen'));
    // The stubbed commit resolves on the next microtask: one pump to enter
    // _Applying, one to let applyImport resolve and insert the snackbar — no
    // magic latency-derived wait.
    await tester.pump();
    await tester.pump();

    expect(
      find.text('De gegevens zijn geïmporteerd (instellingen en 1 spel).'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5)); // drain snackbar
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
