import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/game_mechanics.dart';
import 'package:bonken/models/mini_game.dart';

void main() {
  group('dealerIndexFor', () {
    test('dealer sits to the right of the chooser (chooser − 1, wrapping)', () {
      expect(dealerIndexFor(0), 3);
      expect(dealerIndexFor(1), 0);
      expect(dealerIndexFor(2), 1);
      expect(dealerIndexFor(3), 2);
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
