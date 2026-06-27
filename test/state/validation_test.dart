import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_constraints.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/validation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  // ── Shared fixtures ───────────────────────────────────────────────────────

  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final four = [pa, pb, pc, pd];

  GameSession validSession({String id = kGameId1}) {
    final dt = DateTime(2024);
    return GameSession(
      id: id,
      createdAt: dt,
      updatedAt: dt,
      scoredAt: dt,
      players: four,
      firstDealerId: pa.id,
      rounds: const [],
    );
  }

  // 64 lowercase hex chars (valid sha256 placeholder).
  final fakeHash = 'a' * 64;

  Map<String, dynamic> manifestWith({
    Object? version = 1,
    Object? appVersion = '1.0.0',
    Object? exportedAt = '2024-01-01T00:00:00.000',
    Object? utcOffset = '+00:00',
    Object? contains = const ['games', 'settings'],
    Object? hashes,
    bool omitVersion = false,
    bool omitAppVersion = false,
    bool omitUtcOffset = false,
  }) {
    final c = (contains as List).cast<String>();
    return <String, dynamic>{
      if (!omitVersion) 'version': version,
      if (!omitAppVersion) 'appVersion': appVersion,
      'exportedAt': exportedAt,
      if (!omitUtcOffset) 'utcOffset': utcOffset,
      'contains': contains,
      'hashes':
          hashes ??
          {
            for (final key in c) key: {'algo': 'sha256', 'hash': fakeHash},
          },
    };
  }

  Map<String, dynamic> validSettings() => {
    'version': 1,
    'themeMode': 'system',
    'ruleVariants': {
      'starterVariant': 'dealerStarts',
      'heartsVariant': 'onlyAfterPlayedHeart',
    },
  };

  // ── validateManifest ──────────────────────────────────────────────────────

  group('validateManifest', () {
    test('valid manifest (games + settings) passes', () {
      expect(() => validateManifest(manifestWith()), returnsNormally);
    });

    test('games-only contains passes', () {
      expect(
        () => validateManifest(manifestWith(contains: ['games'])),
        returnsNormally,
      );
    });

    test('settings-only contains passes', () {
      expect(
        () => validateManifest(manifestWith(contains: ['settings'])),
        returnsNormally,
      );
    });

    test('missing version throws', () {
      expect(
        () => validateManifest(manifestWith(omitVersion: true)),
        throwsA(isA<ValidationError>()),
      );
    });

    test('version 0 throws', () {
      expect(
        () => validateManifest(manifestWith(version: 0)),
        throwsA(isA<ValidationError>()),
      );
    });

    test('version as string throws', () {
      expect(
        () => validateManifest(manifestWith(version: '1')),
        throwsA(isA<ValidationError>()),
      );
    });

    test('invalid exportedAt throws', () {
      expect(
        () => validateManifest(manifestWith(exportedAt: 'not-a-date')),
        throwsA(isA<ValidationError>()),
      );
    });

    test('missing utcOffset throws', () {
      expect(
        () => validateManifest(manifestWith(omitUtcOffset: true)),
        throwsA(isA<ValidationError>()),
      );
    });

    test('invalid utcOffset throws', () {
      expect(
        () => validateManifest(manifestWith(utcOffset: 'UTC+2')),
        throwsA(isA<ValidationError>()),
      );
    });

    test('negative utcOffset passes', () {
      expect(
        () => validateManifest(manifestWith(utcOffset: '-05:00')),
        returnsNormally,
      );
    });

    test('empty contains throws', () {
      expect(
        () => validateManifest(manifestWith(contains: [])),
        throwsA(isA<ValidationError>()),
      );
    });

    test('unknown entry in contains throws', () {
      expect(
        () => validateManifest(manifestWith(contains: ['games', 'other'])),
        throwsA(isA<ValidationError>()),
      );
    });

    test('wrong hash algorithm throws', () {
      expect(
        () => validateManifest(
          manifestWith(
            contains: ['games'],
            hashes: {
              'games': {'algo': 'md5', 'hash': fakeHash},
            },
          ),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('hash too short throws', () {
      expect(
        () => validateManifest(
          manifestWith(
            contains: ['games'],
            hashes: {
              'games': {'algo': 'sha256', 'hash': 'abc123'},
            },
          ),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('hash with uppercase chars throws', () {
      expect(
        () => validateManifest(
          manifestWith(
            contains: ['games'],
            hashes: {
              'games': {
                'algo': 'sha256',
                'hash': 'A' * 64, // uppercase not allowed
              },
            },
          ),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('missing hash entry for listed key throws', () {
      expect(
        () => validateManifest(
          manifestWith(
            contains: ['games', 'settings'],
            // only games hash present
            hashes: {
              'games': {'algo': 'sha256', 'hash': fakeHash},
            },
          ),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('missing appVersion passes (optional for dev builds)', () {
      expect(
        () => validateManifest(manifestWith(omitAppVersion: true)),
        returnsNormally,
      );
    });

    test('appVersion as integer throws', () {
      expect(
        () => validateManifest(manifestWith(appVersion: 1)),
        throwsA(isA<ValidationError>()),
      );
    });

    test('empty appVersion throws', () {
      expect(
        () => validateManifest(manifestWith(appVersion: '')),
        throwsA(isA<ValidationError>()),
      );
    });

    test('valid appVersion passes', () {
      expect(
        () => validateManifest(manifestWith(appVersion: '1.2.3')),
        returnsNormally,
      );
    });
  });

  // ── validateMigratedGames ─────────────────────────────────────────────────

  group('validateMigratedGames', () {
    test('empty list passes', () {
      expect(() => validateMigratedGames([]), returnsNormally);
    });

    test('valid game returns parsed session', () {
      final raw = validSession().toJson();
      final result = validateMigratedGames([raw]);
      expect(result.length, 1);
      expect(result.first.id, kGameId1);
    });

    test('two valid games with distinct ids passes', () {
      final raw1 = validSession().toJson();
      final raw2 = validSession(id: kGameId2).toJson();
      final result = validateMigratedGames([raw1, raw2]);
      expect(result.length, 2);
    });

    test('duplicate game id throws', () {
      final raw = validSession().toJson();
      expect(
        () => validateMigratedGames([raw, raw]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('game failing invariants throws as ValidationError', () {
      // Build a session with a Clubs round whose score sum is wrong.
      final dt = DateTime(2024);
      final badSession = GameSession(
        id: kGameId1,
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
            scoresByPlayer: {pa.id: 100, pb.id: 0, pc.id: 0, pd.id: 0},
            input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
            doubles: const DoubleMatrix(),
          ),
        ],
      );
      expect(
        () => validateMigratedGames([badSession.toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    // ── Player id hygiene ────────────────────────────────────────────────────

    Map<String, dynamic> sessionJsonWithPlayerId(String id) {
      final dt = DateTime(2024);
      final base = GameSession(
        id: kGameId1,
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: [pa, pb, pc, pd],
        firstDealerId: pa.id,
        rounds: const [],
      ).toJson();
      // Replace the first player's id and firstDealerId so _validateReferences
      // stays consistent — _checkPlayerIds is then what rejects the bad value.
      (base['players'] as List<Map<String, dynamic>>).first['id'] = id;
      base['firstDealerId'] = id;
      return base;
    }

    test('valid UUID v4 player id passes', () {
      expect(
        () => validateMigratedGames([sessionJsonWithPlayerId(pa.id)]),
        returnsNormally,
      );
    });

    test('non-UUID player id throws', () {
      expect(
        () => validateMigratedGames([sessionJsonWithPlayerId('not-a-uuid')]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('empty player id throws', () {
      expect(
        () => validateMigratedGames([sessionJsonWithPlayerId('')]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('duplicate player id throws', () {
      final base = GameSession(
        id: kGameId1,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        scoredAt: DateTime(2024),
        players: [pa, pb, pc, pd],
        firstDealerId: pa.id,
        rounds: const [],
      ).toJson();
      // Make two players share the same id.
      (base['players'] as List<Map<String, dynamic>>)[1]['id'] = pa.id;
      expect(
        () => validateMigratedGames([base]),
        throwsA(isA<ValidationError>()),
      );
    });

    // ── Player name hygiene ───────────────────────────────────────────────────

    GameSession sessionWithPlayers(List<Player> players) {
      final dt = DateTime(2024);
      return GameSession(
        id: kGameId1,
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: players,
        firstDealerId: players.first.id,
        rounds: const [],
      );
    }

    Player p(String name) => Player(name: name);

    test('player name at max length ($kPlayerNameMaxLength) passes', () {
      final name = 'A' * kPlayerNameMaxLength;
      final players = [p(name), p('B'), p('C'), p('D')];
      expect(
        () => validateMigratedGames([sessionWithPlayers(players).toJson()]),
        returnsNormally,
      );
    });

    test('player name exceeding max length throws', () {
      final name = 'A' * (kPlayerNameMaxLength + 1);
      final players = [p(name), p('B'), p('C'), p('D')];
      expect(
        () => validateMigratedGames([sessionWithPlayers(players).toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('empty player name throws', () {
      final players = [p(''), p('B'), p('C'), p('D')];
      expect(
        () => validateMigratedGames([sessionWithPlayers(players).toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('whitespace-only player name throws', () {
      final players = [p('   '), p('B'), p('C'), p('D')];
      expect(
        () => validateMigratedGames([sessionWithPlayers(players).toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('un-normalized (leading/trailing-space) player name throws', () {
      // The create/edit UI always trims, so an imported " Bob " is foreign data
      // the strict gate must reject rather than store verbatim.
      final players = [p(' Bob '), p('B'), p('C'), p('D')];
      expect(
        () => validateMigratedGames([sessionWithPlayers(players).toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('case-insensitive duplicate player name throws', () {
      final players = [p('Alice'), p('alice'), p('C'), p('D')];
      expect(
        () => validateMigratedGames([sessionWithPlayers(players).toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    // ── Game name hygiene ─────────────────────────────────────────────────────

    GameSession sessionWithGameName(String? name) {
      final dt = DateTime(2024);
      return GameSession(
        id: kGameId1,
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: const [],
        gameName: name,
      );
    }

    test('null gameName passes', () {
      expect(
        () => validateMigratedGames([sessionWithGameName(null).toJson()]),
        returnsNormally,
      );
    });

    test('gameName at max length ($kGameNameMaxLength) passes', () {
      final name = 'A' * kGameNameMaxLength;
      expect(
        () => validateMigratedGames([sessionWithGameName(name).toJson()]),
        returnsNormally,
      );
    });

    test('gameName exceeding max length throws', () {
      final name = 'A' * (kGameNameMaxLength + 1);
      expect(
        () => validateMigratedGames([sessionWithGameName(name).toJson()]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('empty gameName (model invariant violation) throws', () {
      // GameSession.toJson omits gameName when null, so inject via raw JSON.
      final raw = {...sessionWithGameName(null).toJson(), 'gameName': ''};
      expect(
        () => validateMigratedGames([raw]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('whitespace-only gameName throws', () {
      final raw = {...sessionWithGameName(null).toJson(), 'gameName': '   '};
      expect(
        () => validateMigratedGames([raw]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('un-normalized (leading/trailing-space) gameName throws', () {
      // A non-null gameName must already be its trimmed form; an imported
      // " Kerst " is rejected rather than stored un-normalized.
      final raw = {
        ...sessionWithGameName(null).toJson(),
        'gameName': ' Kerst ',
      };
      expect(
        () => validateMigratedGames([raw]),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  // ── validateMigratedSettings ──────────────────────────────────────────────

  group('validateMigratedSettings', () {
    test('valid settings passes', () {
      expect(() => validateMigratedSettings(validSettings()), returnsNormally);
    });

    test('each themeMode value passes', () {
      for (final mode in ['system', 'light', 'dark']) {
        final s = {...validSettings(), 'themeMode': mode};
        expect(() => validateMigratedSettings(s), returnsNormally);
      }
    });

    test('each starterVariant value passes', () {
      for (final v in ['dealerStarts', 'oppositeChooserStarts']) {
        final s = {
          ...validSettings(),
          'ruleVariants': {
            ...validSettings()['ruleVariants'] as Map<String, dynamic>,
            'starterVariant': v,
          },
        };
        expect(() => validateMigratedSettings(s), returnsNormally);
      }
    });

    test('each heartsVariant value passes', () {
      for (final v in ['onlyAfterPlayedHeart', 'graduatedUnlock']) {
        final s = {
          ...validSettings(),
          'ruleVariants': {
            ...validSettings()['ruleVariants'] as Map<String, dynamic>,
            'heartsVariant': v,
          },
        };
        expect(() => validateMigratedSettings(s), returnsNormally);
      }
    });

    test('wrong version throws', () {
      final s = {...validSettings(), 'version': 99};
      expect(
        () => validateMigratedSettings(s),
        throwsA(isA<ValidationError>()),
      );
    });

    test('invalid themeMode throws', () {
      final s = {...validSettings(), 'themeMode': 'neon'};
      expect(
        () => validateMigratedSettings(s),
        throwsA(isA<ValidationError>()),
      );
    });

    test('null themeMode throws', () {
      final s = {...validSettings(), 'themeMode': null};
      expect(
        () => validateMigratedSettings(s),
        throwsA(isA<ValidationError>()),
      );
    });

    test('missing ruleVariants throws', () {
      final s = Map<String, dynamic>.from(validSettings())
        ..remove('ruleVariants');
      expect(
        () => validateMigratedSettings(s),
        throwsA(isA<ValidationError>()),
      );
    });

    test('invalid starterVariant throws', () {
      final s = {
        ...validSettings(),
        'ruleVariants': {
          ...validSettings()['ruleVariants'] as Map<String, dynamic>,
          'starterVariant': 'unknown',
        },
      };
      expect(
        () => validateMigratedSettings(s),
        throwsA(isA<ValidationError>()),
      );
    });

    test('invalid heartsVariant throws', () {
      final s = {
        ...validSettings(),
        'ruleVariants': {
          ...validSettings()['ruleVariants'] as Map<String, dynamic>,
          'heartsVariant': 'unknown',
        },
      };
      expect(
        () => validateMigratedSettings(s),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
