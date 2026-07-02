import 'dart:convert';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/games_envelope_codec.dart';
import 'package:bonken/state/migrations.dart';
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
    List<RoundRecord>? rounds,
    String? gameName,
  }) {
    final dt = DateTime(2024);
    return GameSession(
      id: id,
      createdAt: dt,
      updatedAt: dt,
      scoredAt: dt,
      players: four,
      firstDealerId: four.first.id,
      rounds: rounds ?? const [],
      gameName: gameName,
    );
  }

  RoundRecord clubsRound(int n, Player winner) => RoundRecord(
    roundNumber: n,
    game: const Clubs(),
    chooserId: four[(n - 1) % 4].id,
    scoresByPlayer: {for (final p in four) p.id: p == winner ? 260 : 0},
    input: CountsInput({for (final p in four) p.id: p == winner ? 13 : 0}),
    doubles: const DoubleMatrix(),
  );

  String canonical(GameSession g) => jsonEncode(g.toJson());

  group('round-trip', () {
    test('a single game encodes and decodes exactly', () {
      final original = session(gameName: 'Vrijdagavond');
      final result = GamesEnvelopeCodec.decode(
        GamesEnvelopeCodec.encode([original]),
      );
      expect(result, isA<GamesEnvelopeOk>());
      final games = (result as GamesEnvelopeOk).games;
      expect(games, hasLength(1));
      expect(canonical(games.single), canonical(original));
    });

    test('multiple games round-trip in order', () {
      final a = session(gameName: 'Een');
      final b = session(id: kGameId2, rounds: [clubsRound(1, pa)]);
      final result = GamesEnvelopeCodec.decode(
        GamesEnvelopeCodec.encode([a, b]),
      );
      expect(result, isA<GamesEnvelopeOk>());
      final games = (result as GamesEnvelopeOk).games;
      expect(games.map((g) => g.id), [kGameId1, kGameId2]);
      expect(canonical(games[0]), canonical(a));
      expect(canonical(games[1]), canonical(b));
    });

    test('null game name round-trips as null', () {
      final result = GamesEnvelopeCodec.decode(
        GamesEnvelopeCodec.encode([session()]),
      );
      expect((result as GamesEnvelopeOk).games.single.gameName, isNull);
    });

    test('an empty games list is valid (zero games)', () {
      final result = GamesEnvelopeCodec.decode(GamesEnvelopeCodec.encode([]));
      expect(result, isA<GamesEnvelopeOk>());
      expect((result as GamesEnvelopeOk).games, isEmpty);
    });
  });

  group('version handling', () {
    // Builds an arbitrary envelope so a test can set version / games freely.
    String wrap(Object? envelope) => jsonEncode(envelope);

    test('a newer storage version reports too-new with the game count', () {
      final result = GamesEnvelopeCodec.decode(
        wrap({
          'version': currentStorageVersion + 1,
          'games': [session().toJson(), session(id: kGameId2).toJson()],
        }),
      );
      expect(result, isA<GamesEnvelopeTooNew>());
      final tooNew = result as GamesEnvelopeTooNew;
      expect(tooNew.version, currentStorageVersion + 1);
      expect(tooNew.maxSupported, currentStorageVersion);
      expect(tooNew.count, 2);
    });

    test('an older version is migrated up, then validated', () {
      // A valid current-format game relabelled one version back, with an
      // untrimmed name the v(N-1)→vN normalization step must clean. Exercises
      // the migrate-then-validate branch (transformation itself is covered by
      // migration_runners_test).
      final raw = session().toJson()..['gameName'] = '  Vrijdag  ';
      final result = GamesEnvelopeCodec.decode(
        wrap({
          'version': currentStorageVersion - 1,
          'games': [raw],
        }),
      );
      expect(result, isA<GamesEnvelopeOk>());
      expect((result as GamesEnvelopeOk).games.single.gameName, 'Vrijdag');
    });
  });

  group('invalid input', () {
    String wrap(Object? envelope) => jsonEncode(envelope);

    test('non-JSON is invalid', () {
      expect(
        GamesEnvelopeCodec.decode('not json {'),
        isA<GamesEnvelopeInvalid>(),
      );
      expect(GamesEnvelopeCodec.decode(''), isA<GamesEnvelopeInvalid>());
    });

    test('version 0 is invalid', () {
      expect(
        GamesEnvelopeCodec.decode(wrap({'version': 0, 'games': <dynamic>[]})),
        isA<GamesEnvelopeInvalid>(),
      );
    });

    test('a non-integer version is invalid', () {
      expect(
        GamesEnvelopeCodec.decode(wrap({'version': '1', 'games': <dynamic>[]})),
        isA<GamesEnvelopeInvalid>(),
      );
    });

    test('a missing / non-array games field is invalid', () {
      expect(
        GamesEnvelopeCodec.decode(wrap({'version': currentStorageVersion})),
        isA<GamesEnvelopeInvalid>(),
      );
      expect(
        GamesEnvelopeCodec.decode(
          wrap({'version': currentStorageVersion, 'games': 'nope'}),
        ),
        isA<GamesEnvelopeInvalid>(),
      );
    });

    test(
      'a structurally-broken game is invalid, and reports the parsed count',
      () {
        final result = GamesEnvelopeCodec.decode(
          wrap({
            'version': currentStorageVersion,
            'games': [<String, dynamic>{}],
          }),
        );
        expect(result, isA<GamesEnvelopeInvalid>());
        // The list parsed (one entry) before validation failed.
        expect((result as GamesEnvelopeInvalid).count, 1);
      },
    );
  });
}
