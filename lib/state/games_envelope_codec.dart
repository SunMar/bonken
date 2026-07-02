import 'dart:convert';

import '../models/game_session.dart';
import 'migrations.dart';
import 'validation.dart';

/// Result of decoding a games envelope — a closed set so every transport handles
/// the too-new and invalid cases explicitly.
sealed class GamesEnvelopeResult {
  const GamesEnvelopeResult();
}

/// The envelope was parsed, migrated and validated into [games].
final class GamesEnvelopeOk extends GamesEnvelopeResult {
  const GamesEnvelopeOk(this.games);

  final List<GameSession> games;
}

/// The envelope is well-formed but its storage `version` is newer than this build
/// can migrate — the user should update the app. Reported rather than thrown.
/// [count] is the number of games it declared (surfaced so a transport can still
/// report how many games the payload held).
final class GamesEnvelopeTooNew extends GamesEnvelopeResult {
  const GamesEnvelopeTooNew({
    required this.version,
    required this.maxSupported,
    required this.count,
  });

  final int version;
  final int maxSupported;
  final int count;
}

/// The input is not a valid games envelope, or its content fails migration /
/// validation. [debugReason] is dev-facing only and never shown in the UI.
/// [count] is the number of games parsed before the failure (0 when the failure
/// happened before the games list could be read).
final class GamesEnvelopeInvalid extends GamesEnvelopeResult {
  const GamesEnvelopeInvalid(this.debugReason, {this.count = 0});

  final String debugReason;
  final int count;
}

/// Pure, dependency-free codec for the `{version, games:[…]}` envelope that the
/// Bonken *importable-data* transports share — the single-game QR ([GameQrCodec])
/// and the backup games stream (`BackupCodec`).
///
/// It owns the envelope shape and the **validate-once boundary** (ARCHITECTURE.md
/// §9): [decode] runs [runStorageMigrations] + [validateMigratedGames], so every
/// transport gets migration + validation for free and downstream code trusts the
/// typed [GamesEnvelopeResult]. Nothing transport-specific lives here — no gzip,
/// base64, prefix or ZIP; those belong to the transports on top.
abstract final class GamesEnvelopeCodec {
  /// Serializes [games] into the canonical envelope JSON, stamped at
  /// [currentStorageVersion]. The exact bytes a transport then wraps (gzip+base64
  /// for QR, a ZIP entry for the backup).
  static String encode(List<GameSession> games) {
    final envelope = <String, dynamic>{
      'version': currentStorageVersion,
      'games': <dynamic>[for (final g in games) g.toJson()],
    };
    return jsonEncode(envelope);
  }

  /// Parses, migrates and validates envelope [json] into a [GamesEnvelopeResult].
  /// Never throws — malformed input maps to [GamesEnvelopeInvalid]; a
  /// future-versioned envelope maps to [GamesEnvelopeTooNew].
  ///
  /// Order matters and mirrors the previous per-transport code: version-int check
  /// → games-array check (yields the count) → too-new gate → migrate → validate.
  static GamesEnvelopeResult decode(String json) {
    final List<dynamic> rawGames;
    final int version;
    try {
      final envelope = jsonDecode(json) as Map<String, dynamic>;

      final rawVersion = envelope['version'];
      if (rawVersion is! int || rawVersion < 1) {
        return const GamesEnvelopeInvalid(
          'envelope "version" must be an integer >= 1',
        );
      }
      version = rawVersion;

      final list = envelope['games'];
      if (list is! List) {
        return const GamesEnvelopeInvalid('envelope "games" must be an array');
      }
      rawGames = List<dynamic>.from(list);
    } on Object catch (e) {
      return GamesEnvelopeInvalid('could not decode games envelope: $e');
    }

    final count = rawGames.length;

    if (version > currentStorageVersion) {
      return GamesEnvelopeTooNew(
        version: version,
        maxSupported: currentStorageVersion,
        count: count,
      );
    }

    try {
      final migrated = version < currentStorageVersion
          ? runStorageMigrations(rawGames, fromVersion: version)
          : rawGames;
      return GamesEnvelopeOk(validateMigratedGames(migrated));
    } on ValidationError catch (e) {
      return GamesEnvelopeInvalid(
        'games content invalid: ${e.message}',
        count: count,
      );
    } on Object catch (e) {
      return GamesEnvelopeInvalid(
        'games could not be migrated/validated: $e',
        count: count,
      );
    }
  }
}
