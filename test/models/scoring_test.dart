import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/games/game_catalog.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';

import '_double_matrix_helpers.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Asserts that all scores in [result] sum to [expectedTotal].
  void expectTotal(Map<String, int> scores, int expectedTotal) {
    final sum = scores.values.fold(0, (a, b) => a + b);
    expect(
      sum,
      equals(expectedTotal),
      reason:
          'Score total $sum ≠ expected $expectedTotal\n'
          'Scores: $scores',
    );
  }

  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final players = [pa, pb, pc, pd];

  final noDoubles = DoubleMatrix.empty();

  // ---------------------------------------------------------------------------
  // Catalog
  // ---------------------------------------------------------------------------

  group('Game catalog', () {
    test('contains exactly 13 games', () {
      expect(allGames.length, equals(13));
    });

    test('contains 5 positive and 8 negative games', () {
      final positive = allGames
          .where((g) => g.category == GameCategory.positive)
          .length;
      final negative = allGames
          .where((g) => g.category == GameCategory.negative)
          .length;
      expect(positive, equals(5));
      expect(negative, equals(8));
    });

    test('all game ids are unique', () {
      final ids = allGames.map((g) => g.id).toList();
      expect(ids.toSet().length, equals(ids.length));
    });

    test(
      'every game has a non-empty TextSymbol/SuitSymbol or an IconSymbol',
      () {
        for (final game in allGames) {
          switch (game.symbol) {
            case TextSymbol(:final text):
              expect(
                text.isNotEmpty,
                isTrue,
                reason: '${game.id} text symbol must not be empty',
              );
            case SuitSymbol(:final text):
              expect(
                text.isNotEmpty,
                isTrue,
                reason: '${game.id} suit symbol must not be empty',
              );
            case IconSymbol():
              break;
          }
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Positive games — no doubles
  // ---------------------------------------------------------------------------

  group('Positive games (no doubles)', () {
    const games = [Clubs(), Diamonds(), Hearts(), Spades(), NoTrump()];

    for (final game in games) {
      test('${game.name}: even split (4+4+2+3) = +260', () {
        final result = game.calculateScores(
          input: {
            'counts': {pa.id: 4, pb.id: 4, pc.id: 2, pd.id: 3},
          },
          doubles: noDoubles,
          players: players,
        );
        expect(
          result.scores,
          equals({pa.id: 80, pb.id: 80, pc.id: 40, pd.id: 60}),
        );
        expectTotal(result.scores, 260);
      });

      test('${game.name}: one player wins all 13 tricks', () {
        final result = game.calculateScores(
          input: {
            'counts': {pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0},
          },
          doubles: noDoubles,
          players: players,
        );
        expect(result.scores[pa.id], equals(260));
        expect(result.scores[pb.id], equals(0));
        expectTotal(result.scores, 260);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Duck — doubles/redoubles example from the spec
  // ---------------------------------------------------------------------------

  group('Duck', () {
    const duck = Duck();

    test('no doubles: straight -10 per trick', () {
      final result = duck.calculateScores(
        input: {
          'counts': {pa.id: 4, pb.id: 3, pc.id: 5, pd.id: 1},
        },
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: -40, pb.id: -30, pc.id: -50, pd.id: -10}),
      );
      expectTotal(result.scores, -130);
    });

    // Example from the spec:
    // Doubles: A-B=x1, A-C=x2, A-D=x0, B-C=x0, B-D=x1, C-D=x2
    // Tricks:  A=4, B=3, C=5, D=1
    // Expected: A=-30, B=-40, C=-150, D=+90
    test('spec doubles example: A=-30, B=-40, C=-150, D=+90', () {
      final doubles = DoubleMatrix.empty()
          .withState(pa.id, pb.id, DoubleState.doubled) // A-B = x1
          .withState(pa.id, pc.id, DoubleState.redoubled) // A-C = x2
          // A-D = none (x0) — default
          // B-C = none (x0) — default
          .withState(pb.id, pd.id, DoubleState.doubled) // B-D = x1
          .withState(pc.id, pd.id, DoubleState.redoubled); // C-D = x2

      final result = duck.calculateScores(
        input: {
          'counts': {pa.id: 4, pb.id: 3, pc.id: 5, pd.id: 1},
        },
        doubles: doubles,
        players: players,
      );

      expect(result.scores[pa.id], equals(-30), reason: 'Player A');
      expect(result.scores[pb.id], equals(-40), reason: 'Player B');
      expect(result.scores[pc.id], equals(-150), reason: 'Player C');
      expect(result.scores[pd.id], equals(90), reason: 'Player D');
      expectTotal(result.scores, -130);
    });
  });

  // ---------------------------------------------------------------------------
  // King of Hearts
  // ---------------------------------------------------------------------------

  group('King of Hearts', () {
    const game = KingOfHearts();

    test('player 2 wins the King of Hearts', () {
      final result = game.calculateScores(
        input: {'player': pc.id},
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: 0, pb.id: 0, pc.id: -100, pd.id: 0}),
      );
      expectTotal(result.scores, -100);
    });
  });

  // ---------------------------------------------------------------------------
  // Kings & Jacks
  // ---------------------------------------------------------------------------

  group('Kings & Jacks', () {
    const game = KingsAndJacks();

    test('cards split 2-2-2-2 = -200', () {
      final result = game.calculateScores(
        input: {
          'counts': {pa.id: 2, pb.id: 2, pc.id: 2, pd.id: 2},
        },
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: -50, pb.id: -50, pc.id: -50, pd.id: -50}),
      );
      expectTotal(result.scores, -200);
    });

    test('one player wins all 8 scoring cards', () {
      final result = game.calculateScores(
        input: {
          'counts': {pa.id: 8, pb.id: 0, pc.id: 0, pd.id: 0},
        },
        doubles: noDoubles,
        players: players,
      );
      expect(result.scores[pa.id], equals(-200));
      expectTotal(result.scores, -200);
    });
  });

  // ---------------------------------------------------------------------------
  // Queens
  // ---------------------------------------------------------------------------

  group('Queens', () {
    const game = Queens();

    test('all 4 queens won by different players = -45 each', () {
      final result = game.calculateScores(
        input: {
          'counts': {pa.id: 1, pb.id: 1, pc.id: 1, pd.id: 1},
        },
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: -45, pb.id: -45, pc.id: -45, pd.id: -45}),
      );
      expectTotal(result.scores, -180);
    });
  });

  // ---------------------------------------------------------------------------
  // Heart Points
  // ---------------------------------------------------------------------------

  group('Heart Points', () {
    const game = HeartPoints();

    test('hearts split 4-3-5-1 = -130', () {
      final result = game.calculateScores(
        input: {
          'counts': {pa.id: 4, pb.id: 3, pc.id: 5, pd.id: 1},
        },
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: -40, pb.id: -30, pc.id: -50, pd.id: -10}),
      );
      expectTotal(result.scores, -130);
    });
  });

  // ---------------------------------------------------------------------------
  // 7th / 13th
  // ---------------------------------------------------------------------------

  group('7th / 13th', () {
    const game = SeventhAndThirteenth();

    test('different players win 7th and 13th', () {
      final result = game.calculateScores(
        input: {'player1': pa.id, 'player2': pc.id},
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: -50, pb.id: 0, pc.id: -50, pd.id: 0}),
      );
      expectTotal(result.scores, -100);
    });

    test('same player wins both 7th and 13th', () {
      final result = game.calculateScores(
        input: {'player1': pb.id, 'player2': pb.id},
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: 0, pb.id: -100, pc.id: 0, pd.id: 0}),
      );
      expectTotal(result.scores, -100);
    });
  });

  // ---------------------------------------------------------------------------
  // Final Trick
  // ---------------------------------------------------------------------------

  group('Final Trick', () {
    const game = FinalTrick();

    test('player 3 wins final trick', () {
      final result = game.calculateScores(
        input: {'player': pd.id},
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: 0, pb.id: 0, pc.id: 0, pd.id: -100}),
      );
      expectTotal(result.scores, -100);
    });
  });

  // ---------------------------------------------------------------------------
  // allGames total-points invariant (parameterised sweep)
  // ---------------------------------------------------------------------------

  group('allGames Σscores == totalPoints', () {
    // Builds a minimal valid input that puts all units on player A so the
    // sum of scores equals game.totalPoints regardless of descriptor type.
    Map<String, dynamic> minimalInput(MiniGame game) =>
        switch (game.inputDescriptor) {
          CountsInputDescriptor d => {
            d.inputKey: {pa.id: d.total, pb.id: 0, pc.id: 0, pd.id: 0},
          },
          SinglePlayerInputDescriptor d => {d.inputKey: pa.id},
          DualPlayerInputDescriptor d => {
            d.inputKey1: pa.id,
            d.inputKey2: pa.id,
          },
        };

    for (final game in allGames) {
      test('${game.name}: Σscores == ${game.totalPoints}', () {
        final result = game.calculateScores(
          input: minimalInput(game),
          doubles: noDoubles,
          players: players,
        );
        expectTotal(result.scores, game.totalPoints);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Dominos
  // ---------------------------------------------------------------------------

  group('Dominos', () {
    const game = Dominoes();

    test('player 1 plays the last card', () {
      final result = game.calculateScores(
        input: {'player': pb.id},
        doubles: noDoubles,
        players: players,
      );
      expect(
        result.scores,
        equals({pa.id: 0, pb.id: -100, pc.id: 0, pd.id: 0}),
      );
      expectTotal(result.scores, -100);
    });
  });
}
