import 'package:bonken/state/backup_migrations.dart';
import 'package:bonken/state/migrations.dart';
import 'package:bonken/state/settings_migrations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The runners' contiguity contract must be enforced in release builds (a
  // thrown error), not only by a debug `assert` that compiles out — otherwise a
  // mis-registered / out-of-order step would silently return partially-migrated
  // data stamped at the current version.
  group('runners fail loudly when the chain cannot reach current', () {
    test('runStorageMigrations throws on a start-version mismatch', () {
      // fromVersion 0 matches no registered step, so the chain stalls below
      // currentStorageVersion instead of silently returning the input.
      expect(
        () => runStorageMigrations(<dynamic>[], fromVersion: 0),
        throwsStateError,
      );
    });

    test('runSettingsMigrations throws on a start-version mismatch', () {
      expect(
        () => runSettingsMigrations({'version': 0}, fromVersion: 0),
        throwsStateError,
      );
    });

    test('runBackupMigrations throws on a start-version mismatch', () {
      const BackupData data = (
        manifest: <String, dynamic>{},
        games: null,
        settings: null,
      );
      expect(() => runBackupMigrations(data, fromVersion: 0), throwsStateError);
    });
  });

  group('v10 → v11 normalizes stored names', () {
    test('trims player names and the gameName', () {
      final games = <dynamic>[
        {
          'id': 'g1',
          'gameName': '  Kerst  ',
          'players': [
            {'id': 'p1', 'name': '  Bob  '},
            {'id': 'p2', 'name': 'Ann'},
          ],
        },
      ];
      final game =
          runStorageMigrations(games, fromVersion: 10).single
              as Map<String, dynamic>;
      expect(game['gameName'], 'Kerst');
      final players = game['players'] as List<dynamic>;
      expect((players[0] as Map<String, dynamic>)['name'], 'Bob');
      expect((players[1] as Map<String, dynamic>)['name'], 'Ann');
    });

    test('drops a whitespace-only gameName to null (key removed)', () {
      final games = <dynamic>[
        {
          'id': 'g1',
          'gameName': '   ',
          'players': [
            {'id': 'p1', 'name': 'Bob'},
          ],
        },
      ];
      final game =
          runStorageMigrations(games, fromVersion: 10).single
              as Map<String, dynamic>;
      expect(game.containsKey('gameName'), isFalse);
    });
  });

  group('chain entry below the gameName-normalization step', () {
    // Matches a canonical UUID v4 (version nibble 4, variant 8/9/a/b).
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    // A pre-scoredAt game with a legacy timestamp id, a dead round `gameName`
    // and an untrimmed player name — every field a v8/v9 step touches.
    List<dynamic> legacyGames() => <dynamic>[
      {
        'id': 'ts-1700000000000',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-02-02T00:00:00.000',
        'players': [
          {'id': 'p1', 'name': '  Bob  '},
          {'id': 'p2', 'name': 'Ann'},
        ],
        'firstDealerId': 'p1',
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'clubs',
            'gameName': 'Klaveren',
            'chooserId': 'p1',
            'scores': {'p1': 260, 'p2': 0},
            'input': {
              'counts': [
                {'p1': 13, 'p2': 0},
              ],
            },
          },
        ],
      },
    ];

    test(
      'from v8: copies scoredAt, re-ids to UUID, strips gameName, trims',
      () {
        final game =
            runStorageMigrations(legacyGames(), fromVersion: 8).single
                as Map<String, dynamic>;
        // v8 → v9 copies updatedAt into the new scoredAt field.
        expect(game['scoredAt'], '2024-02-02T00:00:00.000');
        // v9 → v10 replaces the timestamp id with a fresh UUID v4 …
        expect(game['id'], isNot('ts-1700000000000'));
        expect(uuidV4.hasMatch(game['id'] as String), isTrue);
        // … and strips the dead round-level gameName.
        final round = (game['rounds'] as List<dynamic>).single as Map;
        expect(round.containsKey('gameName'), isFalse);
        // v10 → v11 trims stored player names.
        final players = game['players'] as List<dynamic>;
        expect((players[0] as Map<String, dynamic>)['name'], 'Bob');
      },
    );

    test('from v9: skips the scoredAt copy but still re-ids and strips', () {
      final game =
          runStorageMigrations(legacyGames(), fromVersion: 9).single
              as Map<String, dynamic>;
      // Entering at v9 must SKIP the v8 → v9 step, so no scoredAt is injected.
      expect(game.containsKey('scoredAt'), isFalse);
      // The v9 → v10 and v10 → v11 steps still run.
      expect(uuidV4.hasMatch(game['id'] as String), isTrue);
      final round = (game['rounds'] as List<dynamic>).single as Map;
      expect(round.containsKey('gameName'), isFalse);
      final players = game['players'] as List<dynamic>;
      expect((players[0] as Map<String, dynamic>)['name'], 'Bob');
    });
  });

  group('runners are a no-op at the current version', () {
    test('runStorageMigrations returns the input unchanged', () {
      final games = <dynamic>[];
      expect(
        runStorageMigrations(games, fromVersion: currentStorageVersion),
        same(games),
      );
    });

    test('runSettingsMigrations returns the input unchanged', () {
      final settings = {'version': currentSettingsVersion};
      expect(
        runSettingsMigrations(settings, fromVersion: currentSettingsVersion),
        same(settings),
      );
    });
  });
}
