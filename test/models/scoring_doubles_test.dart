import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/games/negative_games.dart';

import '_double_matrix_helpers.dart';

void main() {
  group('Doubles edge cases', () {
    const clubs = Clubs();

    test('Total invariant holds with arbitrary doubles', () {
      // Mixed doubles + redoubles on a positive game should still sum to +260.
      final doubles = DoubleMatrix.empty()
          .withState(0, 1, DoubleState.doubled)
          .withState(0, 2, DoubleState.redoubled)
          .withState(1, 3, DoubleState.doubled)
          .withState(2, 3, DoubleState.redoubled);
      final r = clubs.calculateScores(
        input: {
          'tricks': [4, 3, 5, 1],
        },
        doubles: doubles,
      );
      final sum = r.scores.values.fold(0, (a, b) => a + b);
      expect(sum, 260);
    });

    test('Single double doesn\'t change scores when counts are equal', () {
      // Equal raw counts → diff is zero → multiplier doesn't matter.
      final doubles = DoubleMatrix.empty().withState(
        0,
        1,
        DoubleState.redoubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': [3, 3, 3, 4],
        },
        doubles: doubles,
      );
      expect(r.scores, {0: 60, 1: 60, 2: 60, 3: 80});
    });

    test('Doubled pair amplifies score difference once', () {
      // Tricks 5 vs 1 — diff 4 — doubled = +/-4 tricks of swing for that pair.
      // Player 0: 5 + (5-1)*1 = 9 tricks; Player 1: 1 + (1-5)*1 = -3 tricks.
      // Others unchanged.
      final doubles = DoubleMatrix.empty().withState(0, 1, DoubleState.doubled);
      final r = clubs.calculateScores(
        input: {
          'tricks': [5, 1, 4, 3],
        },
        doubles: doubles,
      );
      expect(r.scores[0], 9 * 20);
      expect(r.scores[1], -3 * 20);
      expect(r.scores[2], 4 * 20);
      expect(r.scores[3], 3 * 20);
    });

    test('Redoubled pair amplifies twice', () {
      // 5 vs 1, redoubled: P0 = 5 + (5-1)*2 = 13; P1 = 1 + (1-5)*2 = -7.
      final doubles = DoubleMatrix.empty().withState(
        0,
        1,
        DoubleState.redoubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': [5, 1, 4, 3],
        },
        doubles: doubles,
      );
      expect(r.scores[0], 13 * 20);
      expect(r.scores[1], -7 * 20);
    });

    test('Negative game total invariant holds with doubles', () {
      const heartPoints = HeartPoints();
      final doubles = DoubleMatrix.empty()
          .withState(0, 3, DoubleState.doubled)
          .withState(1, 2, DoubleState.redoubled);
      final r = heartPoints.calculateScores(
        input: {
          'cards': [4, 3, 5, 1],
        },
        doubles: doubles,
      );
      final sum = r.scores.values.fold(0, (a, b) => a + b);
      expect(sum, -130);
    });

    test('Zero-count player still receives differences from doubles', () {
      // Player 1 has 0 tricks, but is doubled with player 0 who has 13.
      // P0 = 13 + (13-0)*1 = 26 (others: 0)
      // P1 = 0  + (0-13)*1 = -13 (others: 0)
      final doubles = DoubleMatrix.empty().withState(0, 1, DoubleState.doubled);
      final r = clubs.calculateScores(
        input: {
          'tricks': [13, 0, 0, 0],
        },
        doubles: doubles,
      );
      expect(r.scores[0], 26 * 20);
      expect(r.scores[1], -13 * 20);
    });
  });

  group('Positive game variants share scoring', () {
    test('All five positive games produce identical scores for same input', () {
      const games = [Clubs(), Diamonds(), Hearts(), Spades(), NoTrump()];
      final input = {
        'tricks': [4, 4, 2, 3],
      };
      final results = [
        for (final g in games)
          g.calculateScores(input: input, doubles: DoubleMatrix.empty()),
      ];
      for (int i = 1; i < results.length; i++) {
        expect(results[i], results[0]);
      }
    });
  });

  group('Negative games — additional coverage', () {
    test('Duck: one player wins all 13 tricks', () {
      const duck = Duck();
      final r = duck.calculateScores(
        input: {
          'tricks': [13, 0, 0, 0],
        },
        doubles: DoubleMatrix.empty(),
      );
      expect(r.scores[0], -130);
      expect(r.scores[1], 0);
      expect(r.scores[2], 0);
      expect(r.scores[3], 0);
    });

    test('Queens: one player takes all 4 queens', () {
      const queens = Queens();
      final r = queens.calculateScores(
        input: {
          'cards': [4, 0, 0, 0],
        },
        doubles: DoubleMatrix.empty(),
      );
      expect(r.scores[0], -180);
    });

    test('Heart Points: one player takes all 13 hearts', () {
      const hp = HeartPoints();
      final r = hp.calculateScores(
        input: {
          'cards': [0, 13, 0, 0],
        },
        doubles: DoubleMatrix.empty(),
      );
      expect(r.scores[1], -130);
    });
  });

  group('Zero-effective regression', () {
    const clubs = Clubs();

    test('Clubs [13,0,0,0] no doubles → losing players score 0', () {
      final r = clubs.calculateScores(
        input: {
          'tricks': [13, 0, 0, 0],
        },
        doubles: DoubleMatrix.empty(),
      );
      expect(r.scores[1], 0);
      expect(r.scores[2], 0);
      expect(r.scores[3], 0);
      expect(r.scores[0], 260);
    });

    test('Clubs [13,0,0,0] doubled (0,1) → player 1 scores -260', () {
      final doubles = DoubleMatrix.empty().withState(
        0,
        1,
        DoubleState.doubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': [13, 0, 0, 0],
        },
        doubles: doubles,
      );
      expect(r.scores[1], -260);
    });
  });

  group('3-way "Zaal" doubling', () {
    test(
      'Clubs tricks=[5,2,3,3] all 3 pairs (0,x) doubled — total preserved',
      () {
        const clubs = Clubs();
        final doubles = DoubleMatrix.empty()
            .withState(0, 1, DoubleState.doubled)
            .withState(0, 2, DoubleState.doubled)
            .withState(0, 3, DoubleState.doubled);
        final r = clubs.calculateScores(
          input: {
            'tricks': [5, 2, 3, 3],
          },
          doubles: doubles,
        );
        // effective[0] = 5 + 3 + 2 + 2 = 12 → 12*20 = 240
        // effective[1] = 2 + (2-5) = -1 → -20
        // effective[2] = 3 + (3-5) = 1 → 20
        // effective[3] = 3 + (3-5) = 1 → 20
        expect(r.scores[0], 240);
        expect(r.scores[1], -20);
        expect(r.scores[2], 20);
        expect(r.scores[3], 20);
        final sum = r.scores.values.fold(0, (a, b) => a + b);
        expect(sum, 260);
      },
    );

    test(
      'Negative game (Duck) with 3-way doubling preserves total = -130',
      () {
        const duck = Duck();
        final doubles = DoubleMatrix.empty()
            .withState(0, 1, DoubleState.doubled)
            .withState(0, 2, DoubleState.doubled)
            .withState(0, 3, DoubleState.doubled);
        final r = duck.calculateScores(
          input: {
            'tricks': [5, 2, 3, 3],
          },
          doubles: doubles,
        );
        final sum = r.scores.values.fold(0, (a, b) => a + b);
        expect(sum, -130);
      },
    );
  });

  group('SeventhAndThirteenth with doubling', () {
    test('both tricks won by player 1, doubled (1,2)', () {
      const game = SeventhAndThirteenth();
      final doubles = DoubleMatrix.empty().withState(
        1,
        2,
        DoubleState.doubled,
      );
      final r = game.calculateScores(
        input: {'trick7winner': 1, 'trick13winner': 1},
        doubles: doubles,
      );
      // raw counts = [0,2,0,0]
      // effective[1] = 2 + (2-0)*1 = 4 → 4 * -50 = -200
      // effective[2] = 0 + (0-2)*1 = -2 → -2 * -50 = 100
      expect(r.scores[1], -200);
      expect(r.scores[2], 100);
      expect(r.scores[0], 0);
      expect(r.scores[3], 0);
    });
  });
}
