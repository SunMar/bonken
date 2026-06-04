import 'package:bonken/models/game_mechanics.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('seatIndexOf', () {
    final players = [
      Player(name: 'A'),
      Player(name: 'B'),
      Player(name: 'C'),
      Player(name: 'D'),
    ];

    test('returns correct index for each player', () {
      for (var i = 0; i < players.length; i++) {
        expect(seatIndexOf(players, players[i].id), i);
      }
    });

    test('throws StateError on an unknown id', () {
      expect(() => seatIndexOf(players, 'ghost-uuid'), throwsStateError);
    });
  });

  group('dealerIndexFor', () {
    test('dealer sits to the right of the chooser (chooser − 1, wrapping)', () {
      expect(dealerIndexFor(0), 3);
      expect(dealerIndexFor(1), 0);
      expect(dealerIndexFor(2), 1);
      expect(dealerIndexFor(3), 2);
    });
  });

  group('starterIndexFor', () {
    test('dealerStarts: starter == dealer == chooser − 1', () {
      for (var chooser = 0; chooser < playerCount; chooser++) {
        expect(
          starterIndexFor(chooser, StarterVariant.dealerStarts),
          dealerIndexFor(chooser),
          reason: 'chooser $chooser',
        );
      }
    });

    test('oppositeChooserStarts: starter == (chooser − 2) mod 4', () {
      expect(
        starterIndexFor(0, StarterVariant.oppositeChooserStarts),
        (0 - 2 + playerCount) % playerCount, // 2
      );
      expect(
        starterIndexFor(1, StarterVariant.oppositeChooserStarts),
        (1 - 2 + playerCount) % playerCount, // 3
      );
      expect(
        starterIndexFor(2, StarterVariant.oppositeChooserStarts),
        (2 - 2 + playerCount) % playerCount, // 0
      );
      expect(
        starterIndexFor(3, StarterVariant.oppositeChooserStarts),
        (3 - 2 + playerCount) % playerCount, // 1
      );
    });

    test('the two variants always produce different starters', () {
      for (var chooser = 0; chooser < playerCount; chooser++) {
        expect(
          starterIndexFor(chooser, StarterVariant.dealerStarts),
          isNot(starterIndexFor(chooser, StarterVariant.oppositeChooserStarts)),
          reason: 'chooser $chooser',
        );
      }
    });
  });

  group('quotaReached', () {
    test('negative: reached only at or above the 2-game limit', () {
      expect(
        quotaReached(
          GameCategory.negative,
          negativeChosen: 0,
          positiveChosen: 0,
        ),
        isFalse,
      );
      expect(
        quotaReached(
          GameCategory.negative,
          negativeChosen: 1,
          positiveChosen: 9,
        ),
        isFalse,
      );
      expect(
        quotaReached(
          GameCategory.negative,
          negativeChosen: 2,
          positiveChosen: 0,
        ),
        isTrue,
      );
    });

    test('positive: reached only at or above the 1-game limit', () {
      expect(
        quotaReached(
          GameCategory.positive,
          negativeChosen: 9,
          positiveChosen: 0,
        ),
        isFalse,
      );
      expect(
        quotaReached(
          GameCategory.positive,
          negativeChosen: 0,
          positiveChosen: 1,
        ),
        isTrue,
      );
    });

    test('each category checks only its own count', () {
      // A full positive quota does not disable negatives, and vice versa.
      expect(
        quotaReached(
          GameCategory.negative,
          negativeChosen: 0,
          positiveChosen: 1,
        ),
        isFalse,
      );
      expect(
        quotaReached(
          GameCategory.positive,
          negativeChosen: 2,
          positiveChosen: 0,
        ),
        isFalse,
      );
    });
  });
}
