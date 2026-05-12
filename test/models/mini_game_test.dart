import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/mini_game.dart';

void main() {
  group('doublingTurnIndex', () {
    test('chooser themselves is always last (turn 3)', () {
      for (var chooser = 0; chooser < playerCount; chooser++) {
        expect(doublingTurnIndex(chooser, chooser), playerCount - 1);
      }
    });

    test('player to the left of the chooser is first (turn 0)', () {
      for (var chooser = 0; chooser < playerCount; chooser++) {
        final left = (chooser + 1) % playerCount;
        expect(doublingTurnIndex(left, chooser), 0);
      }
    });

    test('every chooser yields a permutation 0..3 over all players', () {
      for (var chooser = 0; chooser < playerCount; chooser++) {
        final turns = [
          for (var p = 0; p < playerCount; p++) doublingTurnIndex(p, chooser),
        ]..sort();
        expect(turns, [0, 1, 2, 3]);
      }
    });

    test('matches the documented order: chooser+1, +2, +3, chooser', () {
      // chooser=2 → expected order: 3, 0, 1, 2 with turns 0..3.
      expect(doublingTurnIndex(3, 2), 0);
      expect(doublingTurnIndex(0, 2), 1);
      expect(doublingTurnIndex(1, 2), 2);
      expect(doublingTurnIndex(2, 2), 3);
    });
  });
}
