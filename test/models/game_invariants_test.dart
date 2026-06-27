import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_invariants.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pa = Player(name: 'A');
  final pb = Player(name: 'B');
  final pc = Player(name: 'C');
  final pd = Player(name: 'D');
  final four = [pa, pb, pc, pd];

  const now = '2024-01-01T00:00:00.000';

  GameSession session({List<Player>? players, List<RoundRecord>? rounds}) {
    final ps = players ?? four;
    final dt = DateTime.parse(now);
    return GameSession(
      id: 's1',
      createdAt: dt,
      updatedAt: dt,
      scoredAt: dt,
      players: ps,
      firstDealerId: ps.first.id,
      rounds: rounds ?? const [],
    );
  }

  // Valid Clubs round: pa takes all 13 tricks (→ 260 pts).
  RoundRecord clubsRound(int n) => RoundRecord(
    roundNumber: n,
    game: const Clubs(),
    chooserId: four[(n - 1) % 4].id,
    scoresByPlayer: {pa.id: 260, pb.id: 0, pc.id: 0, pd.id: 0},
    input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
    doubles: const DoubleMatrix(),
  );

  // Valid KingOfHearts round: pa wins KH (→ -100 pts).
  RoundRecord khRound(int n) => RoundRecord(
    roundNumber: n,
    game: const KingOfHearts(),
    chooserId: four[(n - 1) % 4].id,
    scoresByPlayer: {pa.id: -100, pb.id: 0, pc.id: 0, pd.id: 0},
    input: RecipientInput([pa.id]),
    doubles: const DoubleMatrix(),
  );

  // Valid 7e/13e round: pa wins 7th, pb wins 13th (each -50 → -100 total).
  RoundRecord s7Round(int n) => RoundRecord(
    roundNumber: n,
    game: const SeventhAndThirteenth(),
    chooserId: four[(n - 1) % 4].id,
    scoresByPlayer: {pa.id: -50, pb.id: -50, pc.id: 0, pd.id: 0},
    input: RecipientInput([pa.id, pb.id]),
    doubles: const DoubleMatrix(),
  );

  group('assertGameInvariants — happy path', () {
    test('empty game passes', () {
      expect(() => assertGameInvariants(session()), returnsNormally);
    });

    test('game with rounds passes', () {
      expect(
        () => assertGameInvariants(
          session(rounds: [clubsRound(1), khRound(2), s7Round(3)]),
        ),
        returnsNormally,
      );
    });
  });

  group('player constraints', () {
    test('wrong player count throws', () {
      final dt = DateTime.parse(now);
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: [pa, pb, pc], // only 3
        firstDealerId: pa.id,
        rounds: const [],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });

    test('duplicate player id throws', () {
      // Two players share an id but carry distinct names, so the id check (which
      // runs before the name check) is unambiguously the branch that fires.
      final dupId = Player.fromJson({'id': pc.id, 'name': 'E'});
      final dt = DateTime.parse(now);
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: [pa, pb, pc, dupId],
        firstDealerId: pa.id,
        rounds: const [],
      );
      expect(
        () => assertGameInvariants(s),
        throwsA(
          isA<GameInvariantError>().having(
            (e) => e.message,
            'message',
            contains('duplicate player id'),
          ),
        ),
      );
    });

    test('duplicate player name throws', () {
      final dup = Player(name: 'A'); // same name as pa
      final dt = DateTime.parse(now);
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: [pa, pb, pc, dup],
        firstDealerId: pa.id,
        rounds: const [],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });

    test('duplicate player name throws case-insensitively', () {
      // Uses the shared game_constraints rule, so 'a' collides with 'A'.
      final dup = Player(name: 'a');
      final dt = DateTime.parse(now);
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: [pa, pb, pc, dup],
        firstDealerId: pa.id,
        rounds: const [],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });
  });

  group('round-sequence constraints', () {
    test('rounds exceed max throws', () {
      final rounds = List.generate(13, (i) => clubsRound(i + 1));
      expect(
        () => assertGameInvariants(session(rounds: rounds)),
        throwsA(isA<GameInvariantError>()),
      );
    });

    test('roundNumber gap throws', () {
      final dt = DateTime.parse(now);
      final r2 = RoundRecord(
        roundNumber: 2, // gap: skips 1
        game: const Clubs(),
        chooserId: pa.id,
        scoresByPlayer: {pa.id: 260, pb.id: 0, pc.id: 0, pd.id: 0},
        input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
        doubles: const DoubleMatrix(),
      );
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: [r2],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });
  });

  group('per-round invariants', () {
    test('wrong score count throws', () {
      final dt = DateTime.parse(now);
      final badRound = RoundRecord(
        roundNumber: 1,
        game: const Clubs(),
        chooserId: pa.id,
        scoresByPlayer: {pa.id: 260, pb.id: 0}, // only 2 entries
        input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
        doubles: const DoubleMatrix(),
      );
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: [badRound],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });

    test('wrong score sum throws', () {
      final dt = DateTime.parse(now);
      final badRound = RoundRecord(
        roundNumber: 1,
        game: const Clubs(),
        chooserId: pa.id,
        scoresByPlayer: {
          pa.id: 100,
          pb.id: 0,
          pc.id: 0,
          pd.id: 0, // sum=100, not 260
        },
        input: CountsInput({pa.id: 13, pb.id: 0, pc.id: 0, pd.id: 0}),
        doubles: const DoubleMatrix(),
      );
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: [badRound],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });

    test('counts sum mismatch throws', () {
      final dt = DateTime.parse(now);
      final badRound = RoundRecord(
        roundNumber: 1,
        game: const Clubs(),
        chooserId: pa.id,
        scoresByPlayer: {pa.id: 260, pb.id: 0, pc.id: 0, pd.id: 0},
        input: CountsInput({
          pa.id: 10,
          pb.id: 0,
          pc.id: 0,
          pd.id: 0, // sum=10, not 13
        }),
        doubles: const DoubleMatrix(),
      );
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: [badRound],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });

    test('recipient slot null in completed round throws', () {
      final dt = DateTime.parse(now);
      final badRound = RoundRecord(
        roundNumber: 1,
        game: const KingOfHearts(),
        chooserId: pa.id,
        scoresByPlayer: {pa.id: -100, pb.id: 0, pc.id: 0, pd.id: 0},
        input: const RecipientInput([null]), // null slot — incomplete
        doubles: const DoubleMatrix(),
      );
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: [badRound],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });

    test('count value out of range throws', () {
      final dt = DateTime.parse(now);
      final badRound = RoundRecord(
        roundNumber: 1,
        game: const Clubs(),
        chooserId: pa.id,
        scoresByPlayer: {pa.id: 260, pb.id: 0, pc.id: 0, pd.id: 0},
        // Σ counts is 13 (passes the sum check) but pa wins 14 > total 13 and
        // pb wins -1 < 0 — each individually out of the 0..13 range.
        input: CountsInput({pa.id: 14, pb.id: -1, pc.id: 0, pd.id: 0}),
        doubles: const DoubleMatrix(),
      );
      final s = GameSession(
        id: 's1',
        createdAt: dt,
        updatedAt: dt,
        scoredAt: dt,
        players: four,
        firstDealerId: pa.id,
        rounds: [badRound],
      );
      expect(() => assertGameInvariants(s), throwsA(isA<GameInvariantError>()));
    });
  });
}
