import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/base45.dart';
import 'package:bonken/state/game_qr_codec.dart';
import 'package:bonken/state/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

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
    List<Player>? players,
  }) {
    final dt = DateTime(2024);
    final ps = players ?? four;
    return GameSession(
      id: id,
      createdAt: dt,
      updatedAt: dt,
      scoredAt: dt,
      players: ps,
      firstDealerId: ps.first.id,
      rounds: rounds ?? const [],
      gameName: gameName,
    );
  }

  // A single valid Clubs round where [winner] takes all 13 clubs (260 points).
  RoundRecord clubsRound(int n, Player winner, List<Player> players) =>
      RoundRecord(
        roundNumber: n,
        game: const Clubs(),
        chooserId: players[(n - 1) % 4].id,
        scoresByPlayer: {for (final p in players) p.id: p == winner ? 260 : 0},
        input: CountsInput({
          for (final p in players) p.id: p == winner ? 13 : 0,
        }),
        doubles: const DoubleMatrix(),
      );

  String canonical(GameSession g) => jsonEncode(g.toJson());

  group('GameQrCodec round-trip', () {
    test('empty session preserves id and name', () {
      final original = session(gameName: 'Vrijdagavond');
      final result = GameQrCodec.decode(GameQrCodec.encode(original));
      expect(result, isA<GameQrOk>());
      final game = (result as GameQrOk).game;
      expect(game.id, original.id);
      expect(game.gameName, 'Vrijdagavond');
      expect(canonical(game), canonical(original));
    });

    test('session with a played round round-trips exactly', () {
      final original = session(
        rounds: [clubsRound(1, pa, four)],
        gameName: 'Potje',
      );
      final result = GameQrCodec.decode(GameQrCodec.encode(original));
      expect(result, isA<GameQrOk>());
      expect(canonical((result as GameQrOk).game), canonical(original));
    });

    test('null game name round-trips as null (never empty string)', () {
      final result = GameQrCodec.decode(GameQrCodec.encode(session()));
      expect((result as GameQrOk).game.gameName, isNull);
    });
  });

  group('GameQrCodec size budget (QR scannability)', () {
    test('a full 12-round game with max-length names stays a low-density, '
        'easily scannable QR', () {
      // Worst case: four 20-char player names, a 50-char game name, and 12
      // played rounds. gzip crushes the repeated UUIDs; assert the encoded
      // string stays under a QR-safe budget so future field growth that would
      // break scannability trips this test. (encode() does not validate, so the
      // rounds need not form a rule-valid full game — only realistic size.)
      final longPlayers = [
        Player(name: 'W' * 20),
        Player(name: 'X' * 20),
        Player(name: 'Y' * 20),
        Player(name: 'Z' * 20),
      ];
      final rounds = [
        for (var n = 1; n <= 12; n++)
          clubsRound(n, longPlayers[(n - 1) % 4], longPlayers),
      ];
      final big = session(
        players: longPlayers,
        rounds: rounds,
        gameName: 'G' * 50,
      );
      final encoded = GameQrCodec.encode(big);
      // Scannability is set by the QR *version* (module count), not the raw
      // string length — base45 packs into the denser alphanumeric mode, so a
      // longer string can still yield a smaller code. Render it the way the app
      // does (low error-correction) and assert the module count stays modest.
      // This worst case currently lands at QR v16 (81x81); the 89-module ceiling
      // (v18) leaves headroom for field growth while tripping before a game
      // grows dense enough to hurt phone-to-phone scanning.
      final image = QrImage(
        QrCode(
          payload: QrPayload.fromString(encoded),
          errorCorrectLevel: QrErrorCorrectLevel.low,
        ),
      );
      expect(image.moduleCount, lessThanOrEqualTo(89));
    });
  });

  group('GameQrCodec.decode failures', () {
    // Mirrors encode()'s wrapping but lets the test set an arbitrary envelope.
    String wrap(Object? envelope) {
      final gz = const GZipEncoder().encodeBytes(
        utf8.encode(jsonEncode(envelope)),
      );
      return 'BONKEN:G:1:${Base45.encode(gz)}';
    }

    test('a foreign / non-Bonken string is invalid', () {
      expect(GameQrCodec.decode('https://example.com'), isA<GameQrInvalid>());
      expect(GameQrCodec.decode(''), isA<GameQrInvalid>());
    });

    test('the Bonken prefix with corrupt payload is invalid', () {
      // Lowercase letters are outside the base45 alphabet, so the payload fails
      // to decode before it can be gunzipped.
      expect(
        GameQrCodec.decode('BONKEN:G:1:not-base45!!'),
        isA<GameQrInvalid>(),
      );
    });

    test('an envelope whose game fails validation is invalid', () {
      // A structurally-broken game (empty object) — GameSession.fromJson throws,
      // which the validate boundary turns into a soft invalid result.
      final s = wrap({
        'version': currentStorageVersion,
        'games': [<String, dynamic>{}],
      });
      expect(GameQrCodec.decode(s), isA<GameQrInvalid>());
    });

    test('an envelope with not-exactly-one game is invalid', () {
      final s = wrap({'version': currentStorageVersion, 'games': <dynamic>[]});
      expect(GameQrCodec.decode(s), isA<GameQrInvalid>());
    });

    test('a newer storage version reports too-new (not invalid)', () {
      final s = wrap({
        'version': currentStorageVersion + 1,
        'games': [session().toJson()],
      });
      expect(GameQrCodec.decode(s), isA<GameQrTooNew>());
    });
  });

  group('duplicate detection (canonical-JSON equality)', () {
    test('identical game data compares equal; a rename differs', () {
      final a = session(gameName: 'Zelfde');
      final decodedTwice = GameQrCodec.decode(GameQrCodec.encode(a));
      expect(
        canonical((decodedTwice as GameQrOk).game),
        canonical(a),
        reason: 'same data must produce identical canonical JSON',
      );

      final renamed = session(gameName: 'Anders');
      expect(canonical(renamed), isNot(canonical(a)));
    });
  });
}
