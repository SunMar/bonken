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
import 'package:bonken/state/backup_migrations.dart';
import 'package:bonken/state/export_import_notifier.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/migrations.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  // ── runBackupMigrations ───────────────────────────────────────────────────

  group('runBackupMigrations', () {
    final data = (
      manifest: <String, dynamic>{'version': currentBackupVersion},
      games: null,
      settings: null,
    );

    test('no-op when backupMigrations is empty', () {
      // currentBackupVersion == 1 and backupMigrations == []; calling with
      // fromVersion == currentBackupVersion is a caller error (guard with <),
      // but the runner handles it gracefully in debug builds via the assert.
      // The real path is always fromVersion < currentBackupVersion, which with
      // an empty migration list stalls the assert — so we only test the
      // no-migration-needed case here by verifying the list stays empty.
      expect(backupMigrations, isEmpty);
      expect(currentBackupVersion, 1);
    });

    test('returns same data when no migrations are needed', () {
      // With an empty migration list and fromVersion already at current, the
      // runner returns data unchanged (no steps apply).
      // We call the runner with fromVersion equal to current — the loop is a
      // no-op and the assert passes because v == currentBackupVersion.
      final result = runBackupMigrations(
        data,
        fromVersion: currentBackupVersion,
      );
      expect(result.manifest, same(data.manifest));
      expect(result.games, isNull);
      expect(result.settings, isNull);
    });
  });

  // ── Fixtures ──────────────────────────────────────────────────────────────

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final four = [pa, pb, pc, pd];

  const testAppVersion = AppVersion(version: '2.3.4', buildNumber: '7');

  // Minimal valid settings blob (version 1).
  final validSettingsJson = jsonEncode({
    'version': 1,
    'themeMode': 'system',
    'ruleVariants': {
      'starterVariant': 'dealerStarts',
      'heartsVariant': 'onlyAfterPlayedHeart',
    },
  });

  // A versioned games envelope with one session.
  String gamesEnvelopeWith(List<GameSession> sessions) => jsonEncode({
    'version': currentStorageVersion,
    'games': [for (final s in sessions) s.toJson()],
  });

  // A complete Clubs round.
  RoundRecord clubsRound(int n) => RoundRecord(
    roundNumber: n,
    game: const Clubs(),
    chooserId: four[(n - 1) % 4].id,
    scoresByPlayer: {pa.id: 260, pb.id: 0, pc.id: 0, pd.id: 0},
    input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
    doubles: const DoubleMatrix(),
  );

  GameSession oneSession() {
    final dt = DateTime(2024);
    return GameSession(
      id: kGameId1,
      createdAt: dt,
      updatedAt: dt,
      scoredAt: dt,
      players: four,
      firstDealerId: pa.id,
      rounds: [clubsRound(1)],
    );
  }

  // Decode a ZIP and read a named file as a UTF-8 string.
  String zipFile(Uint8List zip, String name) {
    final archive = ZipDecoder().decodeBytes(zip);
    final file = archive.findFile(name);
    expect(file, isNotNull, reason: '$name not found in archive');
    return utf8.decode(file!.content);
  }

  Map<String, dynamic> zipManifest(Uint8List zip) =>
      jsonDecode(zipFile(zip, 'manifest.json')) as Map<String, dynamic>;

  // ── exportBackup ──────────────────────────────────────────────────────────

  group('exportBackup', () {
    group('All (games + settings)', () {
      test('produces a valid ZIP with all three files', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          GameHistoryNotifier.storageKey,
          gamesEnvelopeWith([oneSession()]),
        );
        await prefs.setString(settingsStorageKey, validSettingsJson);

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: true,
          includeSettings: true,
        );

        final archive = ZipDecoder().decodeBytes(zip);
        expect(archive.findFile('manifest.json'), isNotNull);
        expect(archive.findFile('games.json'), isNotNull);
        expect(archive.findFile('settings.json'), isNotNull);
      });

      test('manifest has correct metadata', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          GameHistoryNotifier.storageKey,
          gamesEnvelopeWith([oneSession()]),
        );
        await prefs.setString(settingsStorageKey, validSettingsJson);

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: true,
          includeSettings: true,
        );

        final manifest = zipManifest(zip);
        expect(manifest['version'], currentBackupVersion);
        expect(manifest['appVersion'], '2.3.4');
        expect(manifest['buildNumber'], '7');
        expect(
          () => DateTime.parse(manifest['exportedAt'] as String),
          returnsNormally,
        );
        expect(manifest['contains'], containsAll(['games', 'settings']));
      });

      test('SHA-256 hashes in manifest match file content', () async {
        final prefs = await SharedPreferences.getInstance();
        final gamesJson = gamesEnvelopeWith([oneSession()]);
        await prefs.setString(GameHistoryNotifier.storageKey, gamesJson);
        await prefs.setString(settingsStorageKey, validSettingsJson);

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: true,
          includeSettings: true,
        );

        final manifest = zipManifest(zip);
        final hashes = manifest['hashes'] as Map<String, dynamic>;

        final gamesActualHash = sha256
            .convert(utf8.encode(gamesJson))
            .toString();
        expect((hashes['games'] as Map)['hash'], gamesActualHash);

        final settingsActualHash = sha256
            .convert(utf8.encode(validSettingsJson))
            .toString();
        expect((hashes['settings'] as Map)['hash'], settingsActualHash);
      });

      test('games.json content round-trips correctly', () async {
        final prefs = await SharedPreferences.getInstance();
        final gamesJson = gamesEnvelopeWith([oneSession()]);
        await prefs.setString(GameHistoryNotifier.storageKey, gamesJson);
        await prefs.setString(settingsStorageKey, validSettingsJson);

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: true,
          includeSettings: true,
        );

        expect(zipFile(zip, 'games.json'), gamesJson);
      });
    });

    group('Games only', () {
      test('no settings.json in archive', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          GameHistoryNotifier.storageKey,
          gamesEnvelopeWith([oneSession()]),
        );

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: true,
          includeSettings: false,
        );

        final archive = ZipDecoder().decodeBytes(zip);
        expect(archive.findFile('settings.json'), isNull);
        expect(archive.findFile('games.json'), isNotNull);
        final manifest = zipManifest(zip);
        expect(manifest['contains'], equals(['games']));
        expect((manifest['hashes'] as Map).containsKey('settings'), isFalse);
      });

      test('zero games falls back to empty envelope', () async {
        // No game_history key written — fresh install.
        final prefs = await SharedPreferences.getInstance();

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: true,
          includeSettings: false,
        );

        final gamesContent =
            jsonDecode(zipFile(zip, 'games.json')) as Map<String, dynamic>;
        expect(gamesContent['version'], currentStorageVersion);
        expect(gamesContent['games'] as List, isEmpty);
      });
    });

    group('Settings only', () {
      test('no games.json in archive', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(settingsStorageKey, validSettingsJson);

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: false,
          includeSettings: true,
        );

        final archive = ZipDecoder().decodeBytes(zip);
        expect(archive.findFile('games.json'), isNull);
        expect(archive.findFile('settings.json'), isNotNull);
        final manifest = zipManifest(zip);
        expect(manifest['contains'], equals(['settings']));
        expect((manifest['hashes'] as Map).containsKey('games'), isFalse);
      });

      test('settings.json content matches stored blob', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(settingsStorageKey, validSettingsJson);

        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: false,
          includeSettings: true,
        );

        expect(zipFile(zip, 'settings.json'), validSettingsJson);
      });
    });

    test('manifest hash algo is sha256', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        GameHistoryNotifier.storageKey,
        gamesEnvelopeWith([oneSession()]),
      );
      await prefs.setString(settingsStorageKey, validSettingsJson);

      final zip = await exportBackup(
        prefs: prefs,
        appVersion: testAppVersion,
        includeGames: true,
        includeSettings: true,
      );

      final manifest = zipManifest(zip);
      final hashes = manifest['hashes'] as Map<String, dynamic>;
      for (final entry in hashes.values) {
        expect((entry as Map)['algo'], 'sha256');
      }
    });

    test('manifest version equals currentBackupVersion', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(settingsStorageKey, validSettingsJson);

      final zip = await exportBackup(
        prefs: prefs,
        appVersion: testAppVersion,
        includeGames: false,
        includeSettings: true,
      );

      final manifest = zipManifest(zip);
      expect(manifest['version'], currentBackupVersion);
    });
  });

  // ── analyzeBackup ─────────────────────────────────────────────────────────

  group('analyzeBackup', () {
    // Helper: build a valid ZIP using exportBackup, then analyze it.
    Future<Uint8List> validZip({
      bool includeGames = true,
      bool includeSettings = true,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        GameHistoryNotifier.storageKey,
        gamesEnvelopeWith([oneSession()]),
      );
      await prefs.setString(settingsStorageKey, validSettingsJson);
      return exportBackup(
        prefs: prefs,
        appVersion: testAppVersion,
        includeGames: includeGames,
        includeSettings: includeSettings,
      );
    }

    group('valid backup — All', () {
      test('returns without throwing', () async {
        await expectLater(analyzeBackup(await validZip()), completes);
      });

      test(
        'appVersionThatCreatedIt and buildNumberThatCreatedIt match',
        () async {
          final a = await analyzeBackup(await validZip());
          expect(a.appVersionThatCreatedIt, '2.3.4');
          expect(a.buildNumberThatCreatedIt, '7');
        },
      );

      test('exportedAt is a recent datetime', () async {
        final before = DateTime.now();
        final a = await analyzeBackup(await validZip());
        final after = DateTime.now();
        expect(
          a.exportedAt.isAfter(before.subtract(const Duration(seconds: 5))),
          isTrue,
        );
        expect(
          a.exportedAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      });

      test('hasGames and hasSettings are true', () async {
        final a = await analyzeBackup(await validZip());
        expect(a.hasGames, isTrue);
        expect(a.hasSettings, isTrue);
      });

      test('gamesCount equals number of exported sessions', () async {
        final a = await analyzeBackup(await validZip());
        expect(a.gamesCount, 1);
      });

      test('canImportGames and canImportSettings are true', () async {
        final a = await analyzeBackup(await validZip());
        expect(a.canImportGames, isTrue);
        expect(a.canImportSettings, isTrue);
      });

      test('both stream statuses are StreamValid', () async {
        final a = await analyzeBackup(await validZip());
        expect(a.gamesStatus, isA<StreamValid>());
        expect(a.settingsStatus, isA<StreamValid>());
      });
    });

    group('valid backup — Games only', () {
      test(
        'hasGames true, hasSettings false, gamesStatus StreamValid',
        () async {
          final a = await analyzeBackup(await validZip(includeSettings: false));
          expect(a.hasGames, isTrue);
          expect(a.hasSettings, isFalse);
          expect(a.canImportGames, isTrue);
          expect(a.canImportSettings, isFalse);
          expect(a.gamesStatus, isA<StreamValid>());
          expect(a.settingsStatus, isA<StreamNotPresent>());
        },
      );
    });

    group('valid backup — Settings only', () {
      test(
        'hasSettings true, hasGames false, settingsStatus StreamValid',
        () async {
          final a = await analyzeBackup(await validZip(includeGames: false));
          expect(a.hasGames, isFalse);
          expect(a.hasSettings, isTrue);
          expect(a.canImportSettings, isTrue);
          expect(a.canImportGames, isFalse);
          expect(a.settingsStatus, isA<StreamValid>());
          expect(a.gamesStatus, isA<StreamNotPresent>());
        },
      );
    });

    group('corrupt archive', () {
      test('random bytes → throws BackupCorrupt', () async {
        await expectLater(
          analyzeBackup(Uint8List.fromList([1, 2, 3, 4, 5])),
          throwsA(isA<BackupCorrupt>()),
        );
      });

      test('empty bytes → throws BackupCorrupt', () async {
        await expectLater(
          analyzeBackup(Uint8List(0)),
          throwsA(isA<BackupCorrupt>()),
        );
      });
    });

    group('manifest errors', () {
      test('missing manifest.json → throws BackupCorrupt', () async {
        // Build a ZIP without manifest.json.
        final archive = Archive()
          ..addFile(ArchiveFile.string('games.json', '{}'));
        final zip = ZipEncoder().encodeBytes(archive);
        await expectLater(analyzeBackup(zip), throwsA(isA<BackupCorrupt>()));
      });

      test('backup version too new → throws BackupTooNew', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(settingsStorageKey, validSettingsJson);
        final zip = await exportBackup(
          prefs: prefs,
          appVersion: testAppVersion,
          includeGames: false,
          includeSettings: true,
        );

        // Patch the manifest version to be too new.
        final archive = ZipDecoder().decodeBytes(zip);
        final originalManifest =
            jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content))
                as Map<String, dynamic>;
        final patchedManifest = {...originalManifest, 'version': 999};
        final newArchive = Archive();
        for (final f in archive.files) {
          if (f.name == 'manifest.json') {
            newArchive.addFile(
              ArchiveFile.string('manifest.json', jsonEncode(patchedManifest)),
            );
          } else {
            newArchive.addFile(f);
          }
        }
        final patchedZip = ZipEncoder().encodeBytes(newArchive);

        await expectLater(
          analyzeBackup(patchedZip),
          throwsA(isA<BackupTooNew>()),
        );
      });
    });

    group('hash mismatch', () {
      test('tampered games.json → throws BackupCorrupt', () async {
        final zip = await validZip();
        final archive = ZipDecoder().decodeBytes(zip);
        final newArchive = Archive();
        for (final f in archive.files) {
          if (f.name == 'games.json') {
            // Replace with different content — hash will mismatch.
            newArchive.addFile(
              ArchiveFile.string('games.json', '{"version":9,"games":[]}'),
            );
          } else {
            newArchive.addFile(f);
          }
        }
        final tampered = ZipEncoder().encodeBytes(newArchive);
        await expectLater(
          analyzeBackup(tampered),
          throwsA(isA<BackupCorrupt>()),
        );
      });
    });

    group('games version', () {
      test(
        'games version too new → gamesStatus StreamVersionTooNew, settings still valid',
        () async {
          // Build a games envelope claiming a future version.
          final futureEnvelope = jsonEncode({
            'version': 9999,
            'games': <dynamic>[],
          });
          final archive = Archive();
          final gamesHash = sha256
              .convert(utf8.encode(futureEnvelope))
              .toString();
          final settingsHash = sha256
              .convert(utf8.encode(validSettingsJson))
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
          archive
            ..addFile(ArchiveFile.string('manifest.json', manifest))
            ..addFile(ArchiveFile.string('games.json', futureEnvelope))
            ..addFile(ArchiveFile.string('settings.json', validSettingsJson));
          final zip = ZipEncoder().encodeBytes(archive);

          final a = await analyzeBackup(zip);
          expect(a.gamesStatus, isA<StreamVersionTooNew>());
          expect(a.hasGames, isTrue);
          expect(a.canImportGames, isFalse);
          // Settings are still valid and importable despite games being too new.
          expect(a.settingsStatus, isA<StreamValid>());
          expect(a.canImportSettings, isTrue);
        },
      );
    });

    group('stream version lower bound', () {
      // Helper: build a hand-crafted archive with the given games/settings
      // envelope content (already hashed correctly in the manifest).
      Uint8List archiveWith({String? gamesEnvelope, String? settingsEnvelope}) {
        final archive = Archive();
        final contains = <String>[];
        final hashes = <String, Map<String, String>>{};

        if (gamesEnvelope != null) {
          archive.addFile(ArchiveFile.string('games.json', gamesEnvelope));
          hashes['games'] = {
            'algo': 'sha256',
            'hash': sha256.convert(utf8.encode(gamesEnvelope)).toString(),
          };
          contains.add('games');
        }
        if (settingsEnvelope != null) {
          archive.addFile(
            ArchiveFile.string('settings.json', settingsEnvelope),
          );
          hashes['settings'] = {
            'algo': 'sha256',
            'hash': sha256.convert(utf8.encode(settingsEnvelope)).toString(),
          };
          contains.add('settings');
        }

        final manifest = jsonEncode({
          'version': currentBackupVersion,
          'appVersion': '1.0.0',
          'exportedAt': DateTime(2024).toIso8601String(),
          'utcOffset': '+00:00',
          'contains': contains,
          'hashes': hashes,
        });
        archive.addFile(ArchiveFile.string('manifest.json', manifest));
        return ZipEncoder().encodeBytes(archive);
      }

      test('games version 0 → gamesStatus StreamCorrupt', () async {
        final badEnvelope = jsonEncode({'version': 0, 'games': <dynamic>[]});
        final a = await analyzeBackup(archiveWith(gamesEnvelope: badEnvelope));
        expect(a.gamesStatus, isA<StreamCorrupt>());
        expect(a.canImportGames, isFalse);
      });

      test('games version as string → gamesStatus StreamCorrupt', () async {
        final badEnvelope = jsonEncode({'version': '1', 'games': <dynamic>[]});
        final a = await analyzeBackup(archiveWith(gamesEnvelope: badEnvelope));
        expect(a.gamesStatus, isA<StreamCorrupt>());
      });

      test('games missing "games" array → gamesStatus StreamCorrupt', () async {
        final badEnvelope = jsonEncode({'version': currentStorageVersion});
        final a = await analyzeBackup(archiveWith(gamesEnvelope: badEnvelope));
        expect(a.gamesStatus, isA<StreamCorrupt>());
      });

      test('settings version 0 → settingsStatus StreamCorrupt', () async {
        final badEnvelope = jsonEncode({
          'version': 0,
          'themeMode': 'system',
          'ruleVariants': {
            'starterVariant': 'dealerStarts',
            'heartsVariant': 'onlyAfterPlayedHeart',
          },
        });
        final a = await analyzeBackup(
          archiveWith(settingsEnvelope: badEnvelope),
        );
        expect(a.settingsStatus, isA<StreamCorrupt>());
        expect(a.canImportSettings, isFalse);
      });

      test(
        'settings version as string → settingsStatus StreamCorrupt',
        () async {
          final badEnvelope = jsonEncode({
            'version': '1',
            'themeMode': 'system',
            'ruleVariants': {
              'starterVariant': 'dealerStarts',
              'heartsVariant': 'onlyAfterPlayedHeart',
            },
          });
          final a = await analyzeBackup(
            archiveWith(settingsEnvelope: badEnvelope),
          );
          expect(a.settingsStatus, isA<StreamCorrupt>());
        },
      );

      test(
        'corrupt games, valid settings → both statuses reported independently',
        () async {
          final badGames = jsonEncode({'version': 0, 'games': <dynamic>[]});
          final goodSettings = validSettingsJson;
          final a = await analyzeBackup(
            archiveWith(
              gamesEnvelope: badGames,
              settingsEnvelope: goodSettings,
            ),
          );
          expect(a.gamesStatus, isA<StreamCorrupt>());
          expect(a.settingsStatus, isA<StreamValid>());
          expect(a.canImportGames, isFalse);
          expect(a.canImportSettings, isTrue);
        },
      );
    });

    group('zip-bomb guard', () {
      test(
        'raw input over the file-size limit → throws BackupCorrupt',
        () async {
          // The honest guard runs before decoding, so the bytes need not be a
          // valid ZIP — only larger than _maxBackupFileBytes (10 MB).
          final tooBig = Uint8List(10 * 1024 * 1024 + 1);
          await expectLater(
            analyzeBackup(tooBig),
            throwsA(isA<BackupCorrupt>()),
          );
        },
      );

      test('archive with too many entries → throws BackupCorrupt', () async {
        final archive = Archive();
        // Add 4 entries (> _maxArchiveEntries = 3).
        for (var i = 0; i < 4; i++) {
          archive.addFile(ArchiveFile.string('extra$i.json', '{}'));
        }
        final zip = ZipEncoder().encodeBytes(archive);
        await expectLater(analyzeBackup(zip), throwsA(isA<BackupCorrupt>()));
      });

      test(
        'archive whose entries exceed uncompressed size limit → throws BackupCorrupt',
        () async {
          // Build an ArchiveFile that reports a size exceeding _maxUncompressedBytes.
          const limit = 10 * 1024 * 1024; // same as _maxUncompressedBytes
          final bigContent = List.filled(limit + 1, 0x41); // 'A' × (limit + 1)
          final archive = Archive()
            ..addFile(ArchiveFile('big.bin', bigContent.length, bigContent));
          final zip = ZipEncoder().encodeBytes(archive);
          await expectLater(analyzeBackup(zip), throwsA(isA<BackupCorrupt>()));
        },
      );
    });

    group('invalid content', () {
      test(
        'game with invalid id → gamesStatus StreamCorrupt, settings still importable',
        () async {
          // Build a session with a bad id (not UUID v4), serialize it, then export.
          final dt = DateTime(2024);
          final badSession = GameSession(
            id: 'bad',
            createdAt: dt,
            updatedAt: dt,
            scoredAt: dt,
            players: four,
            firstDealerId: pa.id,
            rounds: [
              RoundRecord(
                roundNumber: 1,
                game: const Clubs(),
                chooserId: pa.id,
                scoresByPlayer: {pa.id: 1, pb.id: 0, pc.id: 0, pd.id: 0},
                input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
                doubles: const DoubleMatrix(),
              ),
            ],
          );
          final badGamesJson = jsonEncode({
            'version': currentStorageVersion,
            'games': [badSession.toJson()],
          });
          final gamesHash = sha256
              .convert(utf8.encode(badGamesJson))
              .toString();
          final settingsHash = sha256
              .convert(utf8.encode(validSettingsJson))
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
            ..addFile(ArchiveFile.string('games.json', badGamesJson))
            ..addFile(ArchiveFile.string('settings.json', validSettingsJson));
          final zip = ZipEncoder().encodeBytes(archive);

          final a = await analyzeBackup(zip);
          expect(a.gamesStatus, isA<StreamCorrupt>());
          expect(a.canImportGames, isFalse);
          expect(a.hasGames, isTrue);
          // Settings are unaffected — can still be imported.
          expect(a.settingsStatus, isA<StreamValid>());
          expect(a.canImportSettings, isTrue);
        },
      );
    });
  });
}
