import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bonken/models/app_version.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/backup_codec.dart';
import 'package:bonken/state/backup_migrations.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/export_import_notifier.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/migrations.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/theme_mode_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// A [GameHistoryNotifier] whose [replaceAll] always fails — drives the
/// games-write-failure path in [ImportNotifier.applyImport].
class _ThrowingGameHistoryNotifier extends GameHistoryNotifier {
  @override
  Future<void> replaceAll(List<GameSession> sessions) async {
    throw Exception('replaceAll failed');
  }
}

void main() {
  // ── Fixtures ──────────────────────────────────────────────────────────────

  setUp(() => setAsyncPrefs({}));

  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final four = [pa, pb, pc, pd];

  const testAppVersion = AppVersion(version: '1.0.0', buildNumber: '1');

  // Minimal valid settings blob at currentSettingsVersion.
  final validSettingsJson = jsonEncode({
    'version': 1,
    'themeMode': 'dark',
    'ruleVariants': {
      'starterVariant': 'dealerStarts',
      'heartsVariant': 'onlyAfterPlayedHeart',
    },
  });

  GameSession session(String id, {List<RoundRecord>? rounds}) {
    final dt = DateTime(2024);
    return GameSession(
      id: id,
      createdAt: dt,
      updatedAt: dt,
      scoredAt: dt,
      players: four,
      firstDealerId: pa.id,
      rounds: rounds ?? const [],
    );
  }

  RoundRecord clubsRound(int n) => RoundRecord(
    roundNumber: n,
    game: const Clubs(),
    chooserId: four[(n - 1) % 4].id,
    scoresByPlayer: {pa.id: 260, pb.id: 0, pc.id: 0, pd.id: 0},
    input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
    doubles: const DoubleMatrix(),
  );

  // Build a valid ZIP for a given session list and settings blob.
  Future<Uint8List> buildZip({
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
      appVersion: testAppVersion,
      includeGames: sessions != null,
      includeSettings: settingsJson != null,
    );
  }

  // ── GameHistoryNotifier.replaceAll ────────────────────────────────────────

  group('GameHistoryNotifier.replaceAll', () {
    test('replaces state with the given sessions', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Seed one session.
      await container.read(gameHistoryProvider.future);
      await container
          .read(gameHistoryProvider.notifier)
          .saveGame(session(kGameId1, rounds: [clubsRound(1)]));
      expect(container.read(gameHistoryProvider).value!.length, 1);

      // Replace with two sessions.
      final two = [session(kGameId2), session(kGameId3)];
      await container.read(gameHistoryProvider.notifier).replaceAll(two);

      final result = container.read(gameHistoryProvider).value!;
      expect(result.length, 2);
      expect(result.map((s) => s.id).toSet(), {kGameId2, kGameId3});
    });

    test('replaceAll with empty list clears history', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(gameHistoryProvider.future);
      await container
          .read(gameHistoryProvider.notifier)
          .saveGame(session(kGameId1));
      await container.read(gameHistoryProvider.notifier).replaceAll([]);

      expect(container.read(gameHistoryProvider).value, isEmpty);
    });

    test('sessions are persisted to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      await container.read(gameHistoryProvider.notifier).replaceAll([
        session(kGameId1),
      ]);

      final prefs = SharedPreferencesAsync();
      final raw = await prefs.getString(GameHistoryNotifier.storageKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect((decoded['games'] as List).length, 1);
    });
  });

  // ── ImportNotifier.applyImport ────────────────────────────────────────────

  group('ImportNotifier.applyImport', () {
    test('full round-trip: games + settings', () async {
      final zip = await buildZip(
        sessions: [
          session(kGameId1, rounds: [clubsRound(1)]),
        ],
        settingsJson: validSettingsJson,
      );

      // Reset prefs so the container starts clean.
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      final result = await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: true,
            importSettings: true,
          );

      expect(result.gamesImported, 1);
      expect(result.settingsUpdated, isTrue);
      expect(
        container.read(gameHistoryProvider).value!.map((s) => s.id),
        contains(kGameId1),
      );
    });

    test('games-only import: games replaced, settings unchanged', () async {
      final zip = await buildZip(
        sessions: [session(kGameId1), session(kGameId2)],
      );
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      final initialTheme = container.read(themeModeProvider);
      final result = await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: true,
            importSettings: false,
          );

      expect(result.gamesImported, 2);
      expect(result.settingsUpdated, isFalse);
      expect(container.read(themeModeProvider), initialTheme);
    });

    test('settings-only import: settings updated live', () async {
      final zip = await buildZip(settingsJson: validSettingsJson);
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system); // default

      await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: false,
            importSettings: true,
          );

      // validSettingsJson specifies 'dark' — provider must reflect it live.
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('settings-only import preserves an in-progress game (C1)', () async {
      final zip = await buildZip(settingsJson: validSettingsJson);
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      // Start an in-progress game.
      container
          .read(calculatorProvider.notifier)
          .startNewGame(players: four, dealerIndex: 0);
      expect(container.read(calculatorProvider), isA<ActiveSession>());

      await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: false,
            importSettings: true,
          );

      // Settings applied, but the active game must NOT have been reset.
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(container.read(calculatorProvider), isA<ActiveSession>());
    });

    test('games import resets any in-progress game', () async {
      final zip = await buildZip(sessions: [session(kGameId1)]);
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      container
          .read(calculatorProvider.notifier)
          .startNewGame(players: four, dealerIndex: 0);
      expect(container.read(calculatorProvider), isA<ActiveSession>());

      await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: true,
            importSettings: false,
          );

      // Replacing history clears the active session so a debounced autosave
      // can't resurrect the overwritten game.
      expect(container.read(calculatorProvider), isA<NoSession>());
    });

    test('games-write failure preserves the in-progress game', () async {
      final zip = await buildZip(sessions: [session(kGameId1)]);
      setAsyncPrefs({});
      final container = ProviderContainer(
        overrides: [
          gameHistoryProvider.overrideWith(_ThrowingGameHistoryNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      // Keep the autoDispose calculator alive for the whole test.
      final sub = container.listen(calculatorProvider, (_, _) {});
      addTearDown(sub.close);

      container
          .read(calculatorProvider.notifier)
          .startNewGame(players: four, dealerIndex: 0);
      expect(container.read(calculatorProvider), isA<ActiveSession>());

      final backup = await BackupCodec.decode(zip);
      await expectLater(
        container
            .read(importNotifierProvider.notifier)
            .applyImport(backup, importGames: true, importSettings: false),
        throwsA(isA<Exception>()),
      );

      // The write failed AFTER cancelPendingAutosave but BEFORE reset, so the
      // active game survives — the "clean failure" report stays honest.
      expect(container.read(calculatorProvider), isA<ActiveSession>());
    });

    test('imported session count equals gamesImported', () async {
      final sessions = [
        session(kGameId1),
        session(kGameId2),
        session(kGameId3),
      ];
      final zip = await buildZip(sessions: sessions);
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      final result = await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: true,
            importSettings: false,
          );

      expect(result.gamesImported, 3);
    });

    test('pending round survives export → import', () async {
      final pending = PendingRound(gameId: const Clubs().id, chooserId: pa.id);
      final dt = DateTime(2024);
      final withPending = GameSession(
        id: kGameId1,
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: const [],
        pendingRound: pending,
      );
      final zip = await buildZip(sessions: [withPending]);
      setAsyncPrefs({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      await container
          .read(importNotifierProvider.notifier)
          .applyImport(
            await BackupCodec.decode(zip),
            importGames: true,
            importSettings: false,
          );

      final imported = container
          .read(gameHistoryProvider)
          .value!
          .firstWhere((s) => s.id == kGameId1);
      expect(imported.pendingRound, isNotNull);
      expect(imported.pendingRound!.gameId, const Clubs().id);
    });

    test(
      'content-invalid stream is gated at decode, not re-validated at commit',
      () async {
        // Build a backup with VALID games but CONTENT-INVALID settings.
        // The settings version + hash are correct so the ZIP decodes, but the
        // themeMode value is invalid so validateMigratedSettings rejects it.
        final validGamesJson = jsonEncode({
          'version': currentStorageVersion,
          'games': [session(kGameId1).toJson()],
        });
        final badSettingsJson = jsonEncode({
          'version': 1,
          'themeMode': 'neon', // not a valid ThemeMode
          'ruleVariants': {
            'starterVariant': 'dealerStarts',
            'heartsVariant': 'onlyAfterPlayedHeart',
          },
        });
        final gamesHash = sha256
            .convert(utf8.encode(validGamesJson))
            .toString();
        final settingsHash = sha256
            .convert(utf8.encode(badSettingsJson))
            .toString();
        final manifest = jsonEncode({
          'version': currentBackupVersion,
          'appVersion': '1.0.0',
          'exportedAt': DateTime(2024).toIso8601String(),
          'utcOffset': '+00:00',
          'contains': ['games', 'settings'],
          'hashes': {
            'games': {'algo': 'sha256', 'hash': gamesHash},
            'settings': {'algo': 'sha256', 'hash': settingsHash},
          },
        });
        final archive = Archive()
          ..addFile(ArchiveFile.string('manifest.json', manifest))
          ..addFile(ArchiveFile.string('games.json', validGamesJson))
          ..addFile(ArchiveFile.string('settings.json', badSettingsJson));
        final zip = ZipEncoder().encodeBytes(archive);

        // Decode is the single validate pass: the invalid settings stream is
        // flagged StreamCorrupt here, so the UI never offers it and the commit
        // never sees it. Games stay valid and importable.
        final analysis = await BackupCodec.decode(zip);
        expect(analysis.gamesStatus, isA<StreamValid<List<GameSession>>>());
        expect(analysis.settingsStatus, isA<StreamCorrupt>());
        expect(analysis.canImportSettings, isFalse);

        // Committing only the valid stream succeeds with no partial write —
        // the corrupt stream was gated out before commit (no re-validate pass).
        setAsyncPrefs({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(gameHistoryProvider.future);
        final result = await container
            .read(importNotifierProvider.notifier)
            .applyImport(analysis, importGames: true, importSettings: false);
        expect(result.gamesImported, 1);
        expect(result.settingsUpdated, isFalse);
      },
    );
  });
}
