import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('storage converters (inputToCounts / countsToInput)', () {
    final players = [
      for (final n in ['A', 'B', 'C', 'D']) Player(name: n),
    ];
    final ids = [for (final p in players) p.id];

    test('counts game round-trips its per-player distribution', () {
      const game = Clubs();
      final input = CountsInput({ids[0]: 5, ids[1]: 4, ids[2]: 3, ids[3]: 1});
      final stored = game.inputToCounts(input);
      expect(stored, [
        {ids[0]: 5, ids[1]: 4, ids[2]: 3, ids[3]: 1},
      ]);
      expect(game.countsToInput(stored), input);
    });

    test('recipient game round-trips the chosen player', () {
      const game = KingOfHearts();
      final stored = game.inputToCounts(RecipientInput([ids[2]]));
      expect(stored, [
        {ids[2]: 1},
      ]);
      expect(game.countsToInput(stored), RecipientInput([ids[2]]));
    });

    test('recipient game maps a null pick to an empty element', () {
      const game = KingOfHearts();
      expect(game.inputToCounts(const RecipientInput([null])), [
        <String, int>{},
      ]);
      expect(
        game.countsToInput([<String, int>{}]),
        const RecipientInput([null]),
      );
    });

    test(
      'recipient game preserves which player won which trick (positional)',
      () {
        const game = SeventhAndThirteenth();
        final input = RecipientInput([ids[0], ids[2]]);
        final stored = game.inputToCounts(input);
        expect(stored, [
          {ids[0]: 1},
          {ids[2]: 1},
        ]);
        // Same two players, swapped slots → a *different* stored list, proving
        // the 7th-vs-13th distinction survives.
        expect(game.inputToCounts(RecipientInput([ids[2], ids[0]])), [
          {ids[2]: 1},
          {ids[0]: 1},
        ]);
        expect(game.countsToInput(stored), input);
      },
    );

    test('recipient game round-trips a half-filled round (one slot null)', () {
      const game = SeventhAndThirteenth();
      final stored = game.inputToCounts(RecipientInput([ids[1], null]));
      expect(stored, [
        {ids[1]: 1},
        <String, int>{},
      ]);
      expect(game.countsToInput(stored), RecipientInput([ids[1], null]));
    });

    test('recipient slot with two ids is rejected', () {
      const game = KingOfHearts();
      expect(
        () => game.countsToInput([
          {ids[0]: 1, ids[1]: 1},
        ]),
        throwsFormatException,
      );
    });

    test('recipient slot with a count other than 1 is rejected', () {
      const game = KingOfHearts();
      expect(
        () => game.countsToInput([
          {ids[0]: 2},
        ]),
        throwsFormatException,
      );
    });

    test('recipient input with more slots than prompts is rejected', () {
      const game = KingOfHearts(); // one prompt
      expect(
        () => game.countsToInput([
          {ids[0]: 1},
          {ids[1]: 1},
        ]),
        throwsFormatException,
      );
    });

    test('counts input with more than one element is rejected', () {
      const game = Clubs();
      expect(
        () => game.countsToInput([
          {ids[0]: 13, ids[1]: 0, ids[2]: 0, ids[3]: 0},
          {ids[0]: 1},
        ]),
        throwsFormatException,
      );
    });
  });
}
