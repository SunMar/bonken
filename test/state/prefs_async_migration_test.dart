// Guards the one-off legacy `SharedPreferences` → `SharedPreferencesAsync` data
// move wired into `main()` (`migrateLegacyPrefs`). The storage layer now reads
// through `SharedPreferencesAsync` (DataStore on Android); on the first launch
// after the upgrade the package's migration tool copies existing data across.
//
// This is the data-loss surface MODN flagged: a real seeded game history +
// settings blob must survive the move, the app must read it back, and re-running
// must be idempotent (never clobber newer data written after the first launch).
//
// `SharedPreferences.setMockInitialValues` seeds the *legacy* store (the source);
// `setAsyncPrefs()` installs the empty *async* store (the target).

import 'dart:convert';

import 'package:bonken/main.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/migrations.dart' show currentStorageVersion;
import 'package:bonken/state/settings_storage.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

GameSession _sampleSession() {
  final players = [
    for (final n in ['Alice', 'Bob', 'Carol', 'Dan']) Player(name: n),
  ];
  return GameSession(
    id: kGameId1,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: players,
    firstDealerId: players[0].id,
    rounds: [
      RoundRecord(
        roundNumber: 1,
        game: const Dominoes(),
        chooserId: players[1].id,
        scoresByPlayer: {
          players[0].id: -100,
          players[1].id: 0,
          players[2].id: 0,
          players[3].id: 0,
        },
        input: RecipientInput([players[0].id]),
        doubles: const DoubleMatrix(),
      ),
    ],
  );
}

void main() {
  initializeWidgets();

  // Empty async target store before each test; the legacy source is seeded
  // per-test via SharedPreferences.setMockInitialValues.
  setUp(setAsyncPrefs);

  test('copies legacy game history + settings into the async store', () async {
    final session = _sampleSession();
    final gamesBlob = jsonEncode({
      'version': currentStorageVersion,
      'games': [session.toJson()],
    });
    final settingsBlob = jsonEncode(
      settingsToJson(
        const PersistedSettings.defaults().copyWith(themeMode: ThemeMode.dark),
      ),
    );
    SharedPreferences.setMockInitialValues({
      'game_history': gamesBlob,
      'settings': settingsBlob,
    });

    expect(await migrateLegacyPrefs(), isTrue);

    // The async store (what the app now reads) holds the moved blobs verbatim.
    final asyncPrefs = SharedPreferencesAsync();
    expect(await asyncPrefs.getString('game_history'), gamesBlob);
    expect(await asyncPrefs.getString('settings'), settingsBlob);

    // And the storage layer reads them back as real objects, end-to-end.
    final settings = await loadPersistedSettings();
    expect(settings.themeMode, ThemeMode.dark);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final games = await container.read(gameHistoryProvider.future);
    expect(games.single.id, session.id);
    expect(games.single.players.map((p) => p.name), [
      'Alice',
      'Bob',
      'Carol',
      'Dan',
    ]);
  });

  test('is idempotent: a second run never clobbers newer async data', () async {
    final legacyBlob = jsonEncode(
      settingsToJson(
        const PersistedSettings.defaults().copyWith(themeMode: ThemeMode.light),
      ),
    );
    SharedPreferences.setMockInitialValues({'settings': legacyBlob});
    expect(await migrateLegacyPrefs(), isTrue);

    // Simulate the app writing a newer value after the first-launch migration.
    final newerBlob = jsonEncode(
      settingsToJson(
        const PersistedSettings.defaults().copyWith(themeMode: ThemeMode.dark),
      ),
    );
    await SharedPreferencesAsync().setString('settings', newerBlob);

    // A second migration (next launch) must short-circuit and leave it alone.
    expect(await migrateLegacyPrefs(), isTrue);
    expect(await SharedPreferencesAsync().getString('settings'), newerBlob);
  });

  test(
    'fresh install (no legacy data) completes and bootstraps defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await migrateLegacyPrefs(), isTrue);

      final settings = await loadPersistedSettings();
      expect(settings.themeMode, ThemeMode.system);
    },
  );
}
