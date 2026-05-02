import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';

void main() {
  GameSession sample({
    String id = 's1',
    List<RoundSummary>? rounds,
    PendingRound? pending,
  }) {
    final now = DateTime(2024, 1, 1, 12, 0);
    return GameSession(
      id: id,
      createdAt: now,
      updatedAt: now,
      playerNames: const ['A', 'B', 'C', 'D'],
      rounds: rounds ?? const [],
      pendingRound: pending,
    );
  }

  RoundSummary round(int n, Map<int, int> scores) => RoundSummary(
    roundNumber: n,
    gameName: 'Klaveren',
    gameId: 'clubs',
    dealerIndex: (n - 1) % 4,
    chooserIndex: n % 4,
    scores: scores,
  );

  group('finalScores / winnerIndices', () {
    test('Empty session: zero scores, no winners', () {
      final s = sample();
      expect(s.finalScores, {0: 0, 1: 0, 2: 0, 3: 0});
      expect(s.winnerIndices, isEmpty);
    });

    test('Cumulates scores across rounds', () {
      final s = sample(
        rounds: [
          round(1, {0: 100, 1: 50, 2: 80, 3: 30}),
          round(2, {0: -20, 1: 10, 2: 5, 3: 5}),
        ],
      );
      expect(s.finalScores, {0: 80, 1: 60, 2: 85, 3: 35});
      expect(s.winnerIndices, [2]);
    });

    test('winnerIndices returns multiple players on tie', () {
      final s = sample(
        rounds: [
          round(1, {0: 100, 1: 100, 2: 50, 3: 50}),
        ],
      );
      expect(s.winnerIndices..sort(), [0, 1]);
    });

    test('winnerIndices returns all four when everyone is tied', () {
      final tiedNeg = sample(
        rounds: [
          round(1, {0: -50, 1: -50, 2: -50, 3: -50}),
        ],
      );
      expect(tiedNeg.winnerIndices..sort(), [0, 1, 2, 3]);

      final tiedZero = sample(
        rounds: [
          round(1, {0: 0, 1: 0, 2: 0, 3: 0}),
        ],
      );
      expect(tiedZero.winnerIndices..sort(), [0, 1, 2, 3]);
    });

    test('finalScores ignores pendingRound', () {
      final s = sample(
        rounds: [
          round(1, {0: 100, 1: 50, 2: 80, 3: 30}),
        ],
        pending: const PendingRound(
          gameId: 'duck',
          gameName: 'Bukken',
          dealerIndex: 1,
          chooserIndex: 2,
          input: {
            'tricks': [10, 1, 1, 1],
          },
        ),
      );
      // Pending round contributes nothing to finalScores.
      expect(s.finalScores, {0: 100, 1: 50, 2: 80, 3: 30});
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

  group('JSON roundtrip', () {
    test('GameSession with rounds and pending round survives roundtrip', () {
      final original = sample(
        rounds: [
          round(1, {0: 100, 1: 50, 2: 80, 3: 30}),
          RoundSummary(
            roundNumber: 2,
            gameName: 'Bukken',
            gameId: 'duck',
            dealerIndex: 1,
            chooserIndex: 2,
            scores: const {0: -40, 1: -30, 2: -50, 3: -10},
            input: const {
              'tricks': [4, 3, 5, 1],
            },
            doublesJson: DoubleMatrix.empty()
                .withPair(0, 1, DoubleState.doubled, initiator: 0)
                .toJson(),
          ),
        ],
        pending: const PendingRound(
          gameId: 'queens',
          gameName: 'Vrouwen',
          dealerIndex: 2,
          chooserIndex: 3,
          input: {
            'cards': [1, 0, 0, 0],
          },
        ),
      );

      final json = original.toJson();
      final back = GameSession.fromJson(json);

      expect(back.id, original.id);
      expect(back.createdAt, original.createdAt);
      expect(back.updatedAt, original.updatedAt);
      expect(back.playerNames, original.playerNames);
      expect(back.rounds.length, 2);
      expect(back.rounds[0].scores, original.rounds[0].scores);
      expect(back.rounds[1].input, original.rounds[1].input);
      expect(back.rounds[1].doublesJson, isNotNull);
      expect(back.pendingRound, isNotNull);
      expect(back.pendingRound!.gameId, 'queens');
      expect(back.pendingRound!.input, {
        'cards': [1, 0, 0, 0],
      });
    });

    test('GameSession without pendingRound omits the field', () {
      final s = sample();
      expect(s.toJson().containsKey('pendingRound'), isFalse);
    });

    test('RoundSummary roundtrip preserves all fields', () {
      final r = round(5, {0: 10, 1: -10, 2: 0, 3: 0});
      final back = RoundSummary.fromJson(r.toJson());
      expect(back.roundNumber, r.roundNumber);
      expect(back.gameName, r.gameName);
      expect(back.gameId, r.gameId);
      expect(back.dealerIndex, r.dealerIndex);
      expect(back.chooserIndex, r.chooserIndex);
      expect(back.scores, r.scores);
    });

    test('PendingRound roundtrip preserves all fields including doubles', () {
      final p = PendingRound(
        gameId: 'duck',
        gameName: 'Bukken',
        dealerIndex: 1,
        chooserIndex: 2,
        input: const {
          'tricks': [3, 4, 0, 0],
        },
        doublesJson: DoubleMatrix.empty()
            .withPair(0, 1, DoubleState.redoubled, initiator: 1)
            .toJson(),
      );
      final back = PendingRound.fromJson(p.toJson());
      expect(back.gameId, p.gameId);
      expect(back.gameName, p.gameName);
      expect(back.dealerIndex, p.dealerIndex);
      expect(back.chooserIndex, p.chooserIndex);
      expect(back.input, p.input);
      expect(back.doublesJson, isNotNull);
      final m = DoubleMatrix.fromJson(back.doublesJson!);
      expect(m.stateFor(0, 1), DoubleState.redoubled);
      expect(m.initiatorFor(0, 1), 1);
    });
  });
}
