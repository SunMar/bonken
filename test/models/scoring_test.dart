import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/games/game_catalog.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Asserts that all scores in [result] sum to [expectedTotal].
  void expectTotal(Map<int, int> scores, int expectedTotal) {
    final sum = scores.values.fold(0, (a, b) => a + b);
    expect(
      sum,
      equals(expectedTotal),
      reason:
          'Score total $sum ≠ expected $expectedTotal\n'
          'Scores: $scores',
    );
  }

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
            'tricks': [4, 4, 2, 3],
          },
          doubles: noDoubles,
        );
        expect(result.scores, equals({0: 80, 1: 80, 2: 40, 3: 60}));
        expectTotal(result.scores, 260);
      });

      test('${game.name}: one player wins all 13 tricks', () {
        final result = game.calculateScores(
          input: {
            'tricks': [13, 0, 0, 0],
          },
          doubles: noDoubles,
        );
        expect(result.scores[0], equals(260));
        expect(result.scores[1], equals(0));
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
          'tricks': [4, 3, 5, 1],
        },
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: -40, 1: -30, 2: -50, 3: -10}));
      expectTotal(result.scores, -130);
    });

    // Example from the spec:
    // Doubles: A-B=x1, A-C=x2, A-D=x0, B-C=x0, B-D=x1, C-D=x2
    // Tricks:  A=4, B=3, C=5, D=1
    // Expected: A=-30, B=-40, C=-150, D=+90
    test('spec doubles example: A=-30, B=-40, C=-150, D=+90', () {
      final doubles = DoubleMatrix.empty()
          .withState(0, 1, DoubleState.doubled) // A-B = x1
          .withState(0, 2, DoubleState.redoubled) // A-C = x2
          // A-D = none (x0) — default
          // B-C = none (x0) — default
          .withState(1, 3, DoubleState.doubled) // B-D = x1
          .withState(2, 3, DoubleState.redoubled); // C-D = x2

      final result = duck.calculateScores(
        input: {
          'tricks': [4, 3, 5, 1],
        },
        doubles: doubles,
      );

      expect(result.scores[0], equals(-30), reason: 'Player A');
      expect(result.scores[1], equals(-40), reason: 'Player B');
      expect(result.scores[2], equals(-150), reason: 'Player C');
      expect(result.scores[3], equals(90), reason: 'Player D');
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
        input: {'winner': 2},
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: 0, 1: 0, 2: -100, 3: 0}));
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
          'cards': [2, 2, 2, 2],
        },
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: -50, 1: -50, 2: -50, 3: -50}));
      expectTotal(result.scores, -200);
    });

    test('one player wins all 8 scoring cards', () {
      final result = game.calculateScores(
        input: {
          'cards': [8, 0, 0, 0],
        },
        doubles: noDoubles,
      );
      expect(result.scores[0], equals(-200));
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
          'cards': [1, 1, 1, 1],
        },
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: -45, 1: -45, 2: -45, 3: -45}));
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
          'cards': [4, 3, 5, 1],
        },
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: -40, 1: -30, 2: -50, 3: -10}));
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
        input: {'trick7winner': 0, 'trick13winner': 2},
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: -50, 1: 0, 2: -50, 3: 0}));
      expectTotal(result.scores, -100);
    });

    test('same player wins both 7th and 13th', () {
      final result = game.calculateScores(
        input: {'trick7winner': 1, 'trick13winner': 1},
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: 0, 1: -100, 2: 0, 3: 0}));
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
        input: {'winner': 3},
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: 0, 1: 0, 2: 0, 3: -100}));
      expectTotal(result.scores, -100);
    });
  });

  // ---------------------------------------------------------------------------
  // Dominos
  // ---------------------------------------------------------------------------

  group('Dominos', () {
    const game = Dominoes();

    test('player 1 plays the last card', () {
      final result = game.calculateScores(
        input: {'loser': 1},
        doubles: noDoubles,
      );
      expect(result.scores, equals({0: 0, 1: -100, 2: 0, 3: 0}));
      expectTotal(result.scores, -100);
    });
  });
}
