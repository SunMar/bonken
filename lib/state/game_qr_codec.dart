import 'dart:convert';

import 'package:archive/archive.dart';

import '../models/game_session.dart';
import 'base45.dart';
import 'games_envelope_codec.dart';

/// Scheme prefix identifying a Bonken single-game QR payload. The trailing `1`
/// is the QR **transport** format version — bump it (and branch in [GameQrCodec.decode])
/// if the wrapper (compression/encoding) ever changes. It is independent of the
/// inner games-storage `version`, which rides the normal storage migrations.
const String _qrPrefix = 'BONKEN:G:1:';

/// Result of decoding a scanned QR string — a closed set so every caller handles
/// the too-new and invalid cases explicitly.
sealed class GameQrDecodeResult {
  const GameQrDecodeResult();
}

/// The payload was decoded, migrated and validated into a single [GameSession].
final class GameQrOk extends GameQrDecodeResult {
  const GameQrOk(this.game);

  final GameSession game;
}

/// The QR is a Bonken game, but its storage version is newer than this build can
/// migrate — the user should update the app. Reported rather than thrown.
final class GameQrTooNew extends GameQrDecodeResult {
  const GameQrTooNew();
}

/// The scanned string is not a Bonken game QR, or is corrupt / fails validation.
/// [debugReason] is dev-facing only and never shown in the UI.
final class GameQrInvalid extends GameQrDecodeResult {
  const GameQrInvalid(this.debugReason);

  final String debugReason;
}

/// The **QR transport** for sharing a single [GameSession]: `BONKEN:G:1:` +
/// base45(gzip(envelope JSON)). It is a thin wrapper over [GamesEnvelopeCodec] —
/// the envelope shape, migration and validation live there (shared with the
/// backup transport); this file owns only the QR-specific framing (prefix, gzip,
/// [Base45]) and the single-game constraint.
abstract final class GameQrCodec {
  /// Encodes [game] into a QR string.
  ///
  /// gzip is what makes a full game fit a QR: the JSON repeats each player UUID
  /// dozens of times, so it compresses to a fraction of its size. [Base45] (over
  /// base64) then lets the `qr` package use its denser alphanumeric mode, for a
  /// lower QR version and an easier scan — see [Base45] and ARCHITECTURE.md §9.
  static String encode(GameSession game) {
    final jsonBytes = utf8.encode(GamesEnvelopeCodec.encode([game]));
    final gzipped = const GZipEncoder().encodeBytes(jsonBytes);
    return '$_qrPrefix${Base45.encode(gzipped)}';
  }

  /// Decodes a scanned [raw] string back into a [GameSession] (or a typed
  /// failure). Never throws — foreign / malformed / invalid input all map to
  /// [GameQrInvalid]; a future-versioned game maps to [GameQrTooNew].
  static GameQrDecodeResult decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(_qrPrefix)) {
      return const GameQrInvalid('missing Bonken game QR prefix');
    }

    final String json;
    try {
      final gzipped = Base45.decode(trimmed.substring(_qrPrefix.length));
      json = utf8.decode(const GZipDecoder().decodeBytes(gzipped));
    } on Object catch (e) {
      return GameQrInvalid('could not decode QR payload: $e');
    }

    switch (GamesEnvelopeCodec.decode(json)) {
      case GamesEnvelopeTooNew():
        return const GameQrTooNew();
      case GamesEnvelopeInvalid(:final debugReason):
        return GameQrInvalid(debugReason);
      case GamesEnvelopeOk(:final games):
        // A single-game QR must carry exactly one game.
        if (games.length != 1) {
          return GameQrInvalid(
            'QR must contain exactly one game, got ${games.length}',
          );
        }
        return GameQrOk(games.single);
    }
  }
}
