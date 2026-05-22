import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/games/negative_games.dart';

import '_double_matrix_helpers.dart';

void main() {
  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final players = [pa, pb, pc, pd];

  group('Doubles edge cases', () {
    const clubs = Clubs();

    test('Total invariant holds with arbitrary doubles', () {
      // Mixed doubles + redoubles on a positive game should still sum to +260.
      final doubles = DoubleMatrix.empty()
          .withState(pa.id, pb.id, DoubleState.doubled)
          .withState(pa.id, pc.id, DoubleState.redoubled)
          .withState(pb.id, pd.id, DoubleState.doubled)
          .withState(pc.id, pd.id, DoubleState.redoubled);
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 4, pb.id: 3, pc.id: 5, pd.id: 1},
        },
        doubles: doubles,
        players: players,
      );
      final sum = r.scores.values.fold(0, (a, b) => a + b);
      expect(sum, 260);
    });

    test('Single double doesn\'t change scores when counts are equal', () {
      // Equal raw counts → diff is zero → multiplier doesn't matter.
      final doubles = DoubleMatrix.empty().withState(
        pa.id,
        pb.id,
        DoubleState.redoubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 3, pb.id: 3, pc.id: 3, pd.id: 4},
        },
        doubles: doubles,
        players: players,
      );
      expect(r.scores, {pa.id: 60, pb.id: 60, pc.id: 60, pd.id: 80});
    });

    test('Doubled pair amplifies score difference once', () {
      // Tricks 5 vs 1 — diff 4 — doubled = +/-4 tricks of swing for that pair.
      // Player 0: 5 + (5-1)*1 = 9 tricks; Player 1: 1 + (1-5)*1 = -3 tricks.
      // Others unchanged.
      final doubles = DoubleMatrix.empty().withState(
        pa.id,
        pb.id,
        DoubleState.doubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 5, pb.id: 1, pc.id: 4, pd.id: 3},
        },
        doubles: doubles,
        players: players,
      );
      expect(r.scores[pa.id], 9 * 20);
      expect(r.scores[pb.id], -3 * 20);
      expect(r.scores[pc.id], 4 * 20);
      expect(r.scores[pd.id], 3 * 20);
    });

    test('Redoubled pair amplifies twice', () {
      // 5 vs 1, redoubled: P0 = 5 + (5-1)*2 = 13; P1 = 1 + (1-5)*2 = -7.
      final doubles = DoubleMatrix.empty().withState(
        pa.id,
        pb.id,
        DoubleState.redoubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 5, pb.id: 1, pc.id: 4, pd.id: 3},
        },
        doubles: doubles,
        players: players,
      );
      expect(r.scores[pa.id], 13 * 20);
      expect(r.scores[pb.id], -7 * 20);
    });

    test('Negative game total invariant holds with doubles', () {
      const heartPoints = HeartPoints();
      final doubles = DoubleMatrix.empty()
          .withState(pa.id, pd.id, DoubleState.doubled)
          .withState(pb.id, pc.id, DoubleState.redoubled);
      final r = heartPoints.calculateScores(
        input: {
          'cards': {pa.id: 4, pb.id: 3, pc.id: 5, pd.id: 1},
        },
        doubles: doubles,
        players: players,
      );
      final sum = r.scores.values.fold(0, (a, b) => a + b);
      expect(sum, -130);
    });

    test('Zero-count player still receives differences from doubles', () {
      // Player 1 has 0 tricks, but is doubled with player 0 who has 13.
      // P0 = 13 + (13-0)*1 = 26 (others: 0)
      // P1 = 0  + (0-13)*1 = -13 (others: 0)
      final doubles = DoubleMatrix.empty().withState(
        pa.id,
        pb.id,
        DoubleState.doubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0},
        },
        doubles: doubles,
        players: players,
      );
      expect(r.scores[pa.id], 26 * 20);
      expect(r.scores[pb.id], -13 * 20);
    });
  });

  group('Positive game variants share scoring', () {
    test('All five positive games produce identical scores for same input', () {
      const games = [Clubs(), Diamonds(), Hearts(), Spades(), NoTrump()];
      final input = {
        'tricks': {pa.id: 4, pb.id: 4, pc.id: 2, pd.id: 3},
      };
      final results = [
        for (final g in games)
          g.calculateScores(
            input: input,
            doubles: DoubleMatrix.empty(),
            players: players,
          ),
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
          'tricks': {pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0},
        },
        doubles: DoubleMatrix.empty(),
        players: players,
      );
      expect(r.scores[pa.id], -130);
      expect(r.scores[pb.id], 0);
      expect(r.scores[pc.id], 0);
      expect(r.scores[pd.id], 0);
    });

    test('Queens: one player takes all 4 queens', () {
      const queens = Queens();
      final r = queens.calculateScores(
        input: {
          'cards': {pa.id: 4, pb.id: 0, pc.id: 0, pd.id: 0},
        },
        doubles: DoubleMatrix.empty(),
        players: players,
      );
      expect(r.scores[pa.id], -180);
    });

    test('Heart Points: one player takes all 13 hearts', () {
      const hp = HeartPoints();
      final r = hp.calculateScores(
        input: {
          'cards': {pa.id: 0, pb.id: 13, pc.id: 0, pd.id: 0},
        },
        doubles: DoubleMatrix.empty(),
        players: players,
      );
      expect(r.scores[pb.id], -130);
    });
  });

  group('Zero-effective regression', () {
    const clubs = Clubs();

    test('Clubs [13,0,0,0] no doubles → losing players score 0', () {
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0},
        },
        doubles: DoubleMatrix.empty(),
        players: players,
      );
      expect(r.scores[pb.id], 0);
      expect(r.scores[pc.id], 0);
      expect(r.scores[pd.id], 0);
      expect(r.scores[pa.id], 260);
    });

    test('Clubs [13,0,0,0] doubled (0,1) → player 1 scores -260', () {
      final doubles = DoubleMatrix.empty().withState(
        pa.id,
        pb.id,
        DoubleState.doubled,
      );
      final r = clubs.calculateScores(
        input: {
          'tricks': {pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0},
        },
        doubles: doubles,
        players: players,
      );
      expect(r.scores[pb.id], -260);
    });
  });

  group('3-way "Zaal" doubling', () {
    test(
      'Clubs tricks=[5,2,3,3] all 3 pairs (0,x) doubled — total preserved',
      () {
        const clubs = Clubs();
        final doubles = DoubleMatrix.empty()
            .withState(pa.id, pb.id, DoubleState.doubled)
            .withState(pa.id, pc.id, DoubleState.doubled)
            .withState(pa.id, pd.id, DoubleState.doubled);
        final r = clubs.calculateScores(
          input: {
            'tricks': {pa.id: 5, pb.id: 2, pc.id: 3, pd.id: 3},
          },
          doubles: doubles,
          players: players,
        );
        // effective[0] = 5 + 3 + 2 + 2 = 12 → 12*20 = 240
        // effective[1] = 2 + (2-5) = -1 → -20
        // effective[2] = 3 + (3-5) = 1 → 20
        // effective[3] = 3 + (3-5) = 1 → 20
        expect(r.scores[pa.id], 240);
        expect(r.scores[pb.id], -20);
        expect(r.scores[pc.id], 20);
        expect(r.scores[pd.id], 20);
        final sum = r.scores.values.fold(0, (a, b) => a + b);
        expect(sum, 260);
      },
    );

    test('Negative game (Duck) with 3-way doubling preserves total = -130', () {
      const duck = Duck();
      final doubles = DoubleMatrix.empty()
          .withState(pa.id, pb.id, DoubleState.doubled)
          .withState(pa.id, pc.id, DoubleState.doubled)
          .withState(pa.id, pd.id, DoubleState.doubled);
      final r = duck.calculateScores(
        input: {
          'tricks': {pa.id: 5, pb.id: 2, pc.id: 3, pd.id: 3},
        },
        doubles: doubles,
        players: players,
      );
      final sum = r.scores.values.fold(0, (a, b) => a + b);
      expect(sum, -130);
    });
  });

  group('SeventhAndThirteenth with doubling', () {
    test('both tricks won by player 1, doubled (1,2)', () {
      const game = SeventhAndThirteenth();
      final doubles = DoubleMatrix.empty().withState(
        pb.id,
        pc.id,
        DoubleState.doubled,
      );
      final r = game.calculateScores(
        input: {'trick7winner': pb.id, 'trick13winner': pb.id},
        doubles: doubles,
        players: players,
      );
      // raw counts = [0,2,0,0]
      // effective[1] = 2 + (2-0)*1 = 4 → 4 * -50 = -200
      // effective[2] = 0 + (0-2)*1 = -2 → -2 * -50 = 100
      expect(r.scores[pb.id], -200);
      expect(r.scores[pc.id], 100);
      expect(r.scores[pa.id], 0);
      expect(r.scores[pd.id], 0);
    });
  });
}
