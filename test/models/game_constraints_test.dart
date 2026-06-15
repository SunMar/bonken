import 'package:bonken/models/game_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePlayerName', () {
    test('trims surrounding whitespace', () {
      expect(normalizePlayerName('  Alice  '), 'Alice');
    });
  });

  group('normalizeGameName', () {
    test('null / empty / whitespace → null', () {
      expect(normalizeGameName(null), isNull);
      expect(normalizeGameName(''), isNull);
      expect(normalizeGameName('   '), isNull);
    });

    test('non-empty → trimmed value', () {
      expect(normalizeGameName('  Finale  '), 'Finale');
    });
  });

  group('length predicates', () {
    test('player name length boundary', () {
      expect(playerNameLengthValid('A' * kPlayerNameMaxLength), isTrue);
      expect(playerNameLengthValid('A' * (kPlayerNameMaxLength + 1)), isFalse);
      // Trims before measuring.
      expect(
        playerNameLengthValid('  ${'A' * kPlayerNameMaxLength}  '),
        isTrue,
      );
    });

    test('game name length boundary', () {
      expect(gameNameLengthValid('A' * kGameNameMaxLength), isTrue);
      expect(gameNameLengthValid('A' * (kGameNameMaxLength + 1)), isFalse);
    });
  });

  group('allPlayerNamesFilled', () {
    test('true only when every name is non-empty after trim', () {
      expect(allPlayerNamesFilled(['A', 'B', 'C', 'D']), isTrue);
      expect(allPlayerNamesFilled(['A', '', 'C', 'D']), isFalse);
      expect(allPlayerNamesFilled(['A', '   ', 'C', 'D']), isFalse);
    });
  });

  group('duplicatePlayerNameIndices', () {
    test('no duplicates → empty', () {
      expect(duplicatePlayerNameIndices(['A', 'B', 'C', 'D']), isEmpty);
    });

    test('case-insensitive + trimmed collision returns both indices', () {
      expect(duplicatePlayerNameIndices(['Alice', 'Bob', ' alice ', 'D']), {
        0,
        2,
      });
    });

    test(
      'empty / whitespace names are ignored (not treated as duplicates)',
      () {
        expect(duplicatePlayerNameIndices(['', '', 'C', 'D']), isEmpty);
      },
    );

    test('hasDuplicatePlayerNames mirrors the index set', () {
      expect(hasDuplicatePlayerNames(['A', 'a', 'C', 'D']), isTrue);
      expect(hasDuplicatePlayerNames(['A', 'B', 'C', 'D']), isFalse);
    });
  });
}
