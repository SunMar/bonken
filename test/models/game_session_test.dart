import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/models/rule_variants.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed players for all tests. Created once so UUIDs are stable.
  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final testPlayers = [pa, pb, pc, pd];

  GameSession sample({
    String id = 's1',
    List<RoundRecord>? rounds,
    PendingRound? pending,
  }) {
    final now = DateTime(2024, 1, 1, 12);
    return GameSession(
      id: id,
      createdAt: now,
      updatedAt: now,
      scoredAt: now,
      players: testPlayers,
      firstDealerId: pa.id,
      rounds: rounds ?? const [],
      pendingRound: pending,
    );
  }

  // Creates a RoundRecord from a seat-indexed score map, using player UUIDs.
  RoundRecord round(int n, Map<int, int> indexedScores) => RoundRecord(
    roundNumber: n,
    game: const Clubs(),
    chooserId: testPlayers[n % 4].id,
    scoresByPlayer: {
      for (int i = 0; i < 4; i++) testPlayers[i].id: indexedScores[i] ?? 0,
    },
    input: CountsInput({for (final p in testPlayers) p.id: 0}),
    doubles: const DoubleMatrix(),
  );

  group('finalScoresByPlayer / winnerIds', () {
    test('Empty session: zero scores, no winners', () {
      final s = sample();
      expect(s.finalScoresByPlayer, {pa.id: 0, pb.id: 0, pc.id: 0, pd.id: 0});
      expect(s.winnerIds, isEmpty);
    });

    test('Cumulates scores across rounds', () {
      final s = sample(
        rounds: [
          round(1, {0: 100, 1: 50, 2: 80, 3: 30}),
          round(2, {0: -20, 1: 10, 2: 5, 3: 5}),
        ],
      );
      expect(s.finalScoresByPlayer, {
        pa.id: 80,
        pb.id: 60,
        pc.id: 85,
        pd.id: 35,
      });
      expect(s.winnerIds, [pc.id]);
    });

    test('winnerIds returns multiple players on tie', () {
      final s = sample(
        rounds: [
          round(1, {0: 100, 1: 100, 2: 50, 3: 50}),
        ],
      );
      expect(s.winnerIds, unorderedEquals([pa.id, pb.id]));
    });

    test('winnerIds returns all four when everyone is tied', () {
      final tiedNeg = sample(
        rounds: [
          round(1, {0: -50, 1: -50, 2: -50, 3: -50}),
        ],
      );
      expect(tiedNeg.winnerIds, unorderedEquals([pa.id, pb.id, pc.id, pd.id]));

      final tiedZero = sample(
        rounds: [
          round(1, {0: 0, 1: 0, 2: 0, 3: 0}),
        ],
      );
      expect(tiedZero.winnerIds, unorderedEquals([pa.id, pb.id, pc.id, pd.id]));
    });

    test('finalScoresByPlayer ignores pendingRound', () {
      final s = sample(
        rounds: [
          round(1, {0: 100, 1: 50, 2: 80, 3: 30}),
        ],
        pending: PendingRound(
          gameId: 'duck',
          gameName: 'Bukken',
          chooserId: testPlayers[2].id,
          input: CountsInput({pa.id: 10, pb.id: 1, pc.id: 1, pd.id: 1}),
        ),
      );
      expect(s.finalScoresByPlayer, {
        pa.id: 100,
        pb.id: 50,
        pc.id: 80,
        pd.id: 30,
      });
    });
  });

  group('isFinished', () {
    test('false until 12 rounds', () {
      expect(
        sample(
          rounds: [
            for (int i = 1; i <= 11; i++) round(i, {0: 0}),
          ],
        ).isFinished,
        isFalse,
      );
    });

    test('true at exactly 12 rounds', () {
      expect(
        sample(
          rounds: [
            for (int i = 1; i <= 12; i++) round(i, {0: 0}),
          ],
        ).isFinished,
        isTrue,
      );
    });
  });

  group('fromJson corrupt data', () {
    test('unknown gameId throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'no-such-game',
            'gameName': 'Gone',
            'chooserId': pa.id,
            'scores': {pa.id: 0, pb.id: 0, pc.id: 0, pd.id: 0},
            'input': <String, dynamic>{},
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('unknown firstDealerId throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': 'not-a-real-uuid',
        'rounds': <dynamic>[],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling round chooserId throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'king_of_hearts',
            'gameName': 'Heer van harten',
            'chooserId': 'ghost-uuid',
            'scores': {pa.id: 0, pb.id: 0, pc.id: 0, pd.id: 0},
            'input': <String, dynamic>{},
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling round scoresByPlayer key throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'king_of_hearts',
            'gameName': 'Heer van harten',
            'chooserId': pa.id,
            'scores': {pa.id: 0, pb.id: 0, pc.id: 0, 'ghost-uuid': 0},
            'input': <String, dynamic>{},
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling round input counts key throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'duck',
            'gameName': 'Bukken',
            'chooserId': pa.id,
            'scores': {pa.id: -10, pb.id: -10, pc.id: -10, pd.id: -10},
            'input': {
              'counts': [
                {'ghost-uuid': 3},
              ],
            },
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling round doubles pair A throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'king_of_hearts',
            'gameName': 'Heer van harten',
            'chooserId': pa.id,
            'scores': {pa.id: 0, pb.id: 0, pc.id: 0, pd.id: 0},
            'input': <String, dynamic>{},
            'doublesJson': {
              'ghost-uuid,${pb.id}': {'state': 'doubled', 'initiator': pa.id},
            },
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling round doubles pair B throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'king_of_hearts',
            'gameName': 'Heer van harten',
            'chooserId': pa.id,
            'scores': {pa.id: 0, pb.id: 0, pc.id: 0, pd.id: 0},
            'input': <String, dynamic>{},
            'doublesJson': {
              '${pa.id},ghost-uuid': {'state': 'doubled', 'initiator': pa.id},
            },
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling round doubles initiator throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': [
          {
            'roundNumber': 1,
            'gameId': 'king_of_hearts',
            'gameName': 'Heer van harten',
            'chooserId': pa.id,
            'scores': {pa.id: 0, pb.id: 0, pc.id: 0, pd.id: 0},
            'input': <String, dynamic>{},
            'doublesJson': {
              '${pa.id},${pb.id}': {
                'state': 'doubled',
                'initiator': 'ghost-uuid',
              },
            },
          },
        ],
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling pendingRound chooserId throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': <dynamic>[],
        'pendingRound': {
          'gameId': 'duck',
          'gameName': 'Bukken',
          'chooserId': 'ghost-uuid',
          'input': {'counts': <dynamic>[]},
        },
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });

    test('dangling pendingRound input counts key throws on fromJson', () {
      final json = {
        'id': 's1',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': <dynamic>[],
        'pendingRound': {
          'gameId': 'duck',
          'gameName': 'Bukken',
          'chooserId': pa.id,
          'input': {
            'counts': [
              {'ghost-uuid': 2},
            ],
          },
        },
      };
      expect(() => GameSession.fromJson(json), throwsStateError);
    });
  });

  group('JSON roundtrip', () {
    test('GameSession with rounds and pending round survives roundtrip', () {
      final original = sample(
        rounds: [
          round(1, {0: 100, 1: 50, 2: 80, 3: 30}),
          RoundRecord(
            roundNumber: 2,
            game: const Duck(),
            chooserId: testPlayers[2].id,
            scoresByPlayer: {pa.id: -40, pb.id: -30, pc.id: -50, pd.id: -10},
            input: CountsInput({pa.id: 4, pb.id: 3, pc.id: 5, pd.id: 1}),
            doubles: DoubleMatrix.empty().withPair(
              pa.id,
              pb.id,
              DoubleState.doubled,
              initiator: pa.id,
            ),
          ),
        ],
        pending: PendingRound(
          gameId: 'queens',
          gameName: 'Vrouwen',
          chooserId: testPlayers[3].id,
          input: CountsInput({pa.id: 1, pb.id: 0, pc.id: 0, pd.id: 0}),
        ),
      );

      final json = original.toJson();
      final back = GameSession.fromJson(json);

      expect(back.id, original.id);
      expect(back.createdAt, original.createdAt);
      expect(back.updatedAt, original.updatedAt);
      expect(back.displayedPlayerNames, original.displayedPlayerNames);
      expect(back.rounds.length, 2);
      expect(back.rounds[0].scoresByPlayer, original.rounds[0].scoresByPlayer);
      expect(back.rounds[1].input, original.rounds[1].input);
      expect(back.rounds[1].doubles.hasAnyDouble, isTrue);
      expect(back.pendingRound, isNotNull);
      expect(back.pendingRound!.gameId, 'queens');
      expect(
        back.pendingRound!.input,
        CountsInput({pa.id: 1, pb.id: 0, pc.id: 0, pd.id: 0}),
      );
    });

    test('GameSession without pendingRound omits the field', () {
      final s = sample();
      expect(s.toJson().containsKey('pendingRound'), isFalse);
    });

    test('RoundRecord toJson includes all expected fields', () {
      final r = round(5, {0: 10, 1: -10, 2: 0, 3: 0});
      final json = r.toJson();
      expect(json['roundNumber'], r.roundNumber);
      expect(json['gameId'], r.game.id);
      expect(json['gameName'], r.game.name);
      expect(json['chooserId'], r.chooserId);
      expect(json['scores'], r.scoresByPlayer);
    });

    test('PendingRound roundtrip preserves all fields including doubles', () {
      final p = PendingRound(
        gameId: 'duck',
        gameName: 'Bukken',
        chooserId: testPlayers[2].id,
        input: CountsInput({pa.id: 3, pb.id: 4, pc.id: 0, pd.id: 0}),
        doublesJson: DoubleMatrix.empty()
            .withPair(pa.id, pb.id, DoubleState.redoubled, initiator: pb.id)
            .toJson(),
      );
      final back = PendingRound.fromJson(p.toJson());
      expect(back.gameId, p.gameId);
      expect(back.gameName, p.gameName);
      expect(back.chooserId, p.chooserId);
      expect(back.input, p.input);
      expect(back.doublesJson, isNotNull);
      final m = DoubleMatrix.fromJson(back.doublesJson!);
      expect(m.stateFor(pa.id, pb.id), DoubleState.redoubled);
      expect(m.initiatorFor(pa.id, pb.id), pb.id);
    });

    test('variants survive JSON roundtrip', () {
      final now = DateTime(2024, 1, 1, 12);
      final original = GameSession(
        id: 'v-trip',
        createdAt: now,
        updatedAt: now,
        scoredAt: now,
        players: testPlayers,
        firstDealerId: pa.id,
        rounds: const [],
        ruleVariants: const RuleVariants(
          starterVariant: StarterVariant.oppositeChooserStarts,
          heartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      final back = GameSession.fromJson(original.toJson());
      expect(
        back.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(back.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('missing ruleVariants object falls back to defaults', () {
      final json = {
        'id': 'no-variants',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': <dynamic>[],
        // no 'ruleVariants' key
      };
      final session = GameSession.fromJson(json);
      expect(session.ruleVariants.starterVariant, StarterVariant.dealerStarts);
      expect(
        session.ruleVariants.heartsVariant,
        HeartsVariant.onlyAfterPlayedHeart,
      );
    });

    test('unknown variant names inside ruleVariants fall back to defaults', () {
      final json = {
        'id': 'bad-variants',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
        'scoredAt': '2024-01-01T00:00:00.000',
        'players': [for (final p in testPlayers) p.toJson()],
        'firstDealerId': pa.id,
        'rounds': <dynamic>[],
        'ruleVariants': {
          'starterVariant': 'notARealVariant',
          'heartsVariant': 'alsoNotReal',
        },
      };
      final session = GameSession.fromJson(json);
      expect(session.ruleVariants.starterVariant, StarterVariant.dealerStarts);
      expect(
        session.ruleVariants.heartsVariant,
        HeartsVariant.onlyAfterPlayedHeart,
      );
    });

    test('dual 7e/13e round preserves which player won which trick', () {
      // Two different players: A won the 7th, C won the 13th. The persisted
      // counts list is positional ([7th, 13th]) so the distinction survives —
      // a flat {A:1, C:1} map would have lost it.
      final r = RoundRecord(
        roundNumber: 3,
        game: const SeventhAndThirteenth(),
        chooserId: pa.id,
        scoresByPlayer: {pa.id: -50, pb.id: 0, pc.id: -50, pd.id: 0},
        input: RecipientInput([pa.id, pc.id]),
        doubles: const DoubleMatrix(),
      );
      final json = r.toJson();
      expect(json['input'], {
        'counts': [
          {pa.id: 1},
          {pc.id: 1},
        ],
      });
      final back = GameSession.fromJson(
        sample(rounds: [r]).toJson(),
      ).rounds.first;
      expect(back.input, RecipientInput([pa.id, pc.id]));
    });
  });
}
