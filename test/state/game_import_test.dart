import 'dart:convert';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/game_import.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final four = [pa, pb, pc, pd];

  GameSession session({
    String id = kGameId1,
    String? gameName,
    List<RoundRecord>? rounds,
  }) => GameSession(
    id: id,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: four,
    firstDealerId: four.first.id,
    rounds: rounds ?? const [],
    gameName: gameName,
  );

  group('sameGameData', () {
    test('two independently built games with the same data compare equal', () {
      expect(
        sameGameData(session(gameName: 'X'), session(gameName: 'X')),
        isTrue,
      );
    });

    test('a differing field (name) compares unequal', () {
      expect(
        sameGameData(session(gameName: 'X'), session(gameName: 'Y')),
        isFalse,
      );
    });
  });

  group('sameGameData is independent of map key order', () {
    // Builds a doubling matrix by doubling each pair in the given sequence.
    DoubleMatrix doublesInOrder(List<(Player, Player)> pairs) {
      var matrix = const DoubleMatrix();
      for (final (a, b) in pairs) {
        matrix = matrix.withPair(
          a.id,
          b.id,
          DoubleState.doubled,
          initiator: a.id,
        );
      }
      return matrix;
    }

    RoundRecord roundWith(DoubleMatrix doubles) => RoundRecord(
      roundNumber: 1,
      game: const Clubs(),
      chooserId: four[1].id,
      scoresByPlayer: {for (final p in four) p.id: 0},
      input: CountsInput({for (final p in four) p.id: 0}),
      doubles: doubles,
    );

    test('two doubled pairs added in opposite order still compare equal', () {
      // The same game, but its doubling matrix was built in a different sequence
      // — as if one copy was scanned from a QR and the other replayed locally.
      // DoubleMatrix serializes its pairs in insertion order, so...
      final gameA = session(
        rounds: [
          roundWith(doublesInOrder([(pa, pb), (pc, pd)])),
        ],
      );
      final gameB = session(
        rounds: [
          roundWith(doublesInOrder([(pc, pd), (pa, pb)])),
        ],
      );

      // ...the raw JSON differs only by that map's key order (the hazard is real)
      expect(jsonEncode(gameA.toJson()), isNot(jsonEncode(gameB.toJson())));
      // ...but canonicalization makes the comparison see through it.
      expect(sameGameData(gameA, gameB), isTrue);
    });

    test('a genuine difference in the doubles is still unequal', () {
      final gameA = session(
        rounds: [
          roundWith(doublesInOrder([(pa, pb)])),
        ],
      );
      final gameB = session(
        rounds: [
          roundWith(doublesInOrder([(pc, pd)])),
        ],
      );
      expect(sameGameData(gameA, gameB), isFalse);
    });
  });

  group('classifyGameImport', () {
    test('an unknown id is New', () {
      expect(classifyGameImport(session(), const []), isA<GameImportNew>());
      // Also New when other, different-id games exist.
      expect(
        classifyGameImport(session(id: kGameId3), [
          session(),
          session(id: kGameId2),
        ]),
        isA<GameImportNew>(),
      );
    });

    test(
      'a same-id game with identical data is Identical (carries the existing)',
      () {
        final existing = session(gameName: 'Zelfde');
        final result = classifyGameImport(session(gameName: 'Zelfde'), [
          session(id: kGameId2),
          existing,
        ]);
        expect(result, isA<GameImportIdentical>());
        expect((result as GameImportIdentical).existing.id, existing.id);
      },
    );

    test(
      'a same-id game with different data is Conflict (carries the existing)',
      () {
        final existing = session(gameName: 'Oud');
        final result = classifyGameImport(session(gameName: 'Nieuw'), [
          existing,
        ]);
        expect(result, isA<GameImportConflict>());
        expect((result as GameImportConflict).existing.gameName, 'Oud');
      },
    );
  });
}
