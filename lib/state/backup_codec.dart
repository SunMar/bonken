import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/app_version.dart';
import '../models/game_session.dart';
import 'backup_migrations.dart';
import 'migrations.dart';
import 'settings_migrations.dart';
import 'validation.dart';

// Maximum size of the raw (compressed) backup file we will even attempt to
// decode. This guard reads the *actual* input length, which cannot lie, so it
// is the honest first line of defence. A backup for hundreds of games is well
// under 1 MB; 10 MB is generous.
const int _maxBackupFileBytes = 10 * 1024 * 1024;

// Maximum total uncompressed size across all archive entries. Best-effort
// against a zip bomb: it sums each entry's *declared* uncompressed size, which
// a crafted archive could understate, so it complements rather than replaces
// the raw-file-size guard above. 10 MB is generous for a real backup.
const int _maxUncompressedBytes = 10 * 1024 * 1024;

// Maximum number of entries in the archive (manifest + games + settings = 3).
const int _maxArchiveEntries = 3;

// ---------------------------------------------------------------------------
// Exception types
// ---------------------------------------------------------------------------

/// Base class for exceptions thrown by [BackupCodec.decode] on hard structural
/// failures. Hard failures prevent any stream from being processed.
/// Per-stream soft failures (wrong version, corrupt content) are expressed via
/// [StreamStatus] fields on [DecodedBackup].
sealed class BackupImportException implements Exception {
  const BackupImportException();
}

/// Thrown when the backup was created by a newer version of Bonken and cannot
/// be read by this version of the app.
final class BackupTooNew extends BackupImportException {
  const BackupTooNew();
}

/// Thrown when the backup ZIP is unreadable or structurally corrupt.
final class BackupCorrupt extends BackupImportException {
  const BackupCorrupt(this.debugReason);

  /// Dev-facing description. Never displayed in the UI.
  final String debugReason;

  @override
  String toString() => 'BackupCorrupt: $debugReason';
}

// ---------------------------------------------------------------------------
// Stream status
// ---------------------------------------------------------------------------

/// Analysis result for a single stream (games or settings) inside a backup.
sealed class StreamStatus {
  const StreamStatus();
}

/// The stream was not included in this backup.
final class StreamNotPresent extends StreamStatus {
  const StreamNotPresent();
}

/// The stream is present but was written by a newer app version.
final class StreamVersionTooNew extends StreamStatus {
  const StreamVersionTooNew({
    required this.streamVersion,
    required this.maxSupported,
  });
  final int streamVersion;
  final int maxSupported;
}

/// The stream is present and version-compatible, but its content is corrupt.
final class StreamCorrupt extends StreamStatus {
  const StreamCorrupt(this.debugReason);

  /// Dev-facing description. Never displayed in the UI.
  final String debugReason;
}

/// The stream is present, version-compatible, content-valid, and ready to
/// import. Carries the parsed, validated [value] (the games list or the
/// settings envelope) so the commit consumes exactly what was validated here —
/// there is no second decode/validate pass, and an invalid stream simply has no
/// [StreamValid] to hand a payload to.
final class StreamValid<T> extends StreamStatus {
  const StreamValid(this.value);

  final T value;
}

// ---------------------------------------------------------------------------
// Decode result
// ---------------------------------------------------------------------------

/// Everything [BackupCodec.decode] learns about a backup before any writes.
///
/// [BackupCodec.decode] throws [BackupImportException] for hard structural
/// failures (unreadable ZIP, missing manifest, hash mismatch, version too new).
/// When it returns, this object describes what the backup contains: each
/// stream's status is a [StreamStatus] subtype, and — when valid — its parsed,
/// validated payload rides on the [StreamValid] (surfaced via [games] /
/// [settings]) ready for the commit.
class DecodedBackup {
  const DecodedBackup({
    required this.appVersionThatCreatedIt,
    required this.buildNumberThatCreatedIt,
    required this.exportedAt,
    required this.gamesStatus,
    required this.settingsStatus,
    this.gamesCount = 0,
  });

  /// App version string from the manifest (e.g. `"1.2.3"`), or `''` if absent.
  final String appVersionThatCreatedIt;

  /// Build number from the manifest (e.g. `"45"`), or `''` if absent.
  final String buildNumberThatCreatedIt;

  /// Parsed `exportedAt` timestamp.
  final DateTime exportedAt;

  /// Analysis result for the games stream.
  final StreamStatus gamesStatus;

  /// Analysis result for the settings stream.
  final StreamStatus settingsStatus;

  /// Number of [GameSession] objects in the games stream. Reported even when
  /// the stream is version-too-new (so the UI can still show the count).
  final int gamesCount;

  /// The validated game sessions ready to commit, or `null` when the games
  /// stream is absent/unimportable. Non-null exactly when [gamesStatus] is a
  /// [StreamValid] — the type makes a mismatch unrepresentable.
  List<GameSession>? get games {
    final status = gamesStatus;
    return status is StreamValid<List<GameSession>> ? status.value : null;
  }

  /// The validated, migrated settings envelope ready to commit, or `null` when
  /// the settings stream is absent/unimportable. Non-null exactly when
  /// [settingsStatus] is a [StreamValid].
  Map<String, dynamic>? get settings {
    final status = settingsStatus;
    return status is StreamValid<Map<String, dynamic>> ? status.value : null;
  }

  /// Whether the backup includes a games stream (present but possibly unimportable).
  bool get hasGames => gamesStatus is! StreamNotPresent;

  /// Whether the backup includes a settings stream (present but possibly unimportable).
  bool get hasSettings => settingsStatus is! StreamNotPresent;

  /// Whether the games stream is ready to import.
  bool get canImportGames => gamesStatus is StreamValid;

  /// Whether the settings stream is ready to import.
  bool get canImportSettings => settingsStatus is StreamValid;
}

// ---------------------------------------------------------------------------
// Codec
// ---------------------------------------------------------------------------

/// Pure, dependency-free backup-format codec: ZIP / manifest / SHA-256 / version
/// structure. Holds no Riverpod / prefs / platform state — the effectful gather
/// (export) and commit (import) live in `export_import_notifier.dart`.
///
/// Per-stream migrate + validate is delegated to the owners' existing pure
/// functions (`runStorageMigrations` + `validateMigratedGames`,
/// `runSettingsMigrations` + `validateMigratedSettings`, `runBackupMigrations` +
/// `validateManifest`), so this layer owns *format* logic only.
abstract final class BackupCodec {
  /// Encodes already-serialized stream envelopes into a shareable ZIP archive.
  ///
  /// The ZIP contains:
  /// - `manifest.json` — metadata, SHA-256 hashes and version info.
  /// - `games.json`    — raw versioned SharedPreferences blob (when [gamesJson] is non-null).
  /// - `settings.json` — raw versioned SharedPreferences blob (when [settingsJson] is non-null).
  ///
  /// Both blobs are stored verbatim; the import path runs the normal migration
  /// runners on them, so no up-front conversion happens here. [appVersion.version]
  /// is `null` for dev builds.
  static Uint8List encode({
    required AppVersion appVersion,
    String? gamesJson,
    String? settingsJson,
  }) {
    assert(
      gamesJson != null || settingsJson != null,
      'Must include at least one stream.',
    );
    final archive = Archive();
    final contains = <String>[];
    final hashes = <String, Map<String, String>>{};

    void addStream(String key, String json) {
      archive.addFile(ArchiveFile.string('$key.json', json));
      hashes[key] = {'algo': 'sha256', 'hash': _sha256Hex(json)};
      contains.add(key);
    }

    if (gamesJson != null) addStream('games', gamesJson);
    if (settingsJson != null) addStream('settings', settingsJson);

    final now = DateTime.now();
    final manifest = <String, dynamic>{
      'version': currentBackupVersion,
      'appVersion': appVersion.version,
      'buildNumber': appVersion.buildNumber,
      'exportedAt': now.toIso8601String(),
      'utcOffset': _formatUtcOffset(now.timeZoneOffset),
      'contains': contains,
      'hashes': hashes,
    };
    archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));

    return ZipEncoder().encodeBytes(archive);
  }

  /// Hex SHA-256 of [content] — the single hash function used on both the
  /// producing (manifest) and verifying (integrity-check) sides, so the two
  /// can't diverge.
  static String _sha256Hex(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  /// Formats a timezone [offset] as the `+HH:MM` / `-HH:MM` string the manifest
  /// records (and `validateManifest` checks against `^[+-]\d{2}:\d{2}$`).
  static String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.abs().inHours.toString().padLeft(2, '0');
    final mm = (offset.abs().inMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hh:$mm';
  }

  /// Returns a [StreamCorrupt] when a stream envelope's `version` is not an
  /// `int >= 1`, else null (the two stream decoders report rather than throw).
  /// [label] is the dev-facing stream name (`Games` / `Settings`).
  static StreamCorrupt? _streamVersionError(Object? rawVersion, String label) {
    if (rawVersion is! int || rawVersion < 1) {
      return StreamCorrupt('$label stream: "version" must be an integer >= 1.');
    }
    return null;
  }

  /// Reads [zipBytes], validates all contained streams, and returns a summary
  /// with the validated payloads attached — the single decode + validate pass.
  ///
  /// **No writes are performed.** The result feeds `ImportNotifier.applyImport`,
  /// which commits the already-validated [DecodedBackup.games] /
  /// [DecodedBackup.settings] without re-decoding or re-validating.
  ///
  /// Throws [BackupTooNew] when the backup was made by a newer app version.
  /// Throws [BackupCorrupt] for any other hard structural failure. Both streams
  /// are always fully evaluated — soft per-stream failures (wrong version,
  /// corrupt content) are expressed via [DecodedBackup.gamesStatus] /
  /// [DecodedBackup.settingsStatus], not by throwing.
  ///
  /// Although `async`, the decode + SHA-256 work runs synchronously on whichever
  /// isolate calls it (there is no `await` in the body). The codec stays pure, so
  /// production offloads this to a background isolate via the `decodeBackupProvider`
  /// seam (`Isolate.run`), keeping a large backup off the UI frame; direct callers
  /// — and widget tests, which can't drive a real isolate under the fake-async
  /// clock — decode inline on the calling isolate.
  static Future<DecodedBackup> decode(Uint8List zipBytes) async {
    _checkInputSize(zipBytes);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } on Object catch (e) {
      throw BackupCorrupt('Could not decode ZIP: $e');
    }

    // Zip-bomb / tamper guard (ARCHITECTURE.md §9).
    _checkZipBomb(archive);

    // ── Manifest: decode, migrate, validate ────────────────────────────────
    // Order mirrors the streams: version-check → migrate → validate, so an old
    // manifest is brought up to the current schema before it is validated.

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const BackupCorrupt('manifest.json not found in archive.');
    }

    Map<String, dynamic> manifest;
    try {
      manifest =
          jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    } on Object catch (e) {
      throw BackupCorrupt('manifest.json could not be decoded: $e');
    }

    final rawVersion = manifest['version'];
    if (rawVersion is! int || rawVersion < 1) {
      throw const BackupCorrupt('Manifest: "version" must be an integer >= 1.');
    }
    if (rawVersion > currentBackupVersion) {
      throw const BackupTooNew();
    }
    if (rawVersion < currentBackupVersion) {
      manifest = runBackupMigrations((
        manifest: manifest,
        games: null,
        settings: null,
      ), fromVersion: rawVersion).manifest;
    }

    try {
      validateManifest(manifest);
    } on ValidationError catch (e) {
      throw BackupCorrupt(e.message);
    }

    final contains = (manifest['contains'] as List).cast<String>();
    final hashes = manifest['hashes'] as Map<String, dynamic>;

    // ── Entry allowlist ─────────────────────────────────────────────────────
    // A backup holds exactly the manifest plus one file per declared stream.
    // Reject any extra/junk/directory entry the manifest does not account for —
    // the readers below address files by name and would silently ignore the
    // rest. Checked after the version gate so a newer backup still reports
    // BackupTooNew rather than "unexpected entry".
    final allowedEntries = {
      'manifest.json',
      for (final key in contains) '$key.json',
    };
    for (final file in archive.files) {
      if (!allowedEntries.contains(file.name)) {
        throw BackupCorrupt('Unexpected archive entry "${file.name}".');
      }
    }

    // ── Integrity check ─────────────────────────────────────────────────────
    // All hashes are known from the (now-trusted) manifest; verify every listed
    // stream in one pass before decoding any content. This catches tampering
    // and missing files before any stream data is read.

    for (final key in contains) {
      final file = archive.findFile('$key.json');
      if (file == null) {
        throw BackupCorrupt('manifest lists "$key" but $key.json is missing.');
      }
      final content = utf8.decode(file.content);
      final expectedHash =
          (hashes[key] as Map<String, dynamic>)['hash'] as String;
      if (_sha256Hex(content) != expectedHash) {
        throw BackupCorrupt('Integrity check failed: $key.json hash mismatch.');
      }
    }

    // ── Per-stream decode ────────────────────────────────────────────────────
    // File presence and hashes are verified; decode each stream independently
    // so a problem in one (wrong version, corrupt content) leaves the other
    // importable.
    final (gamesStatus, gamesCount) = _decodeGamesStream(
      archive,
      present: contains.contains('games'),
    );
    final settingsStatus = _decodeSettingsStream(
      archive,
      present: contains.contains('settings'),
    );

    return DecodedBackup(
      appVersionThatCreatedIt: (manifest['appVersion'] as String?) ?? '',
      buildNumberThatCreatedIt: (manifest['buildNumber'] as String?) ?? '',
      exportedAt: DateTime.parse(manifest['exportedAt'] as String),
      gamesStatus: gamesStatus,
      settingsStatus: settingsStatus,
      gamesCount: gamesCount,
    );
  }

  /// Decodes, migrates and validates the games stream, returning its status and
  /// the game count (reported even when the stream is unimportable).
  static (StreamStatus, int) _decodeGamesStream(
    Archive archive, {
    required bool present,
  }) {
    if (!present) return (const StreamNotPresent(), 0);

    // Everything past presence operates on content that is only
    // transit-hash-verified, never trusted: the manifest author picks both the
    // bytes and their hash. So the whole parse → migrate → validate pipeline is
    // wrapped — any failure becomes a soft StreamCorrupt instead of an untyped
    // throw escaping decode(), keeping the other stream independently importable.
    var count = 0;
    try {
      final envelope =
          jsonDecode(utf8.decode(archive.findFile('games.json')!.content))
              as Map<String, dynamic>;
      final rawVersion = envelope['version'];
      final versionError = _streamVersionError(rawVersion, 'Games');
      if (versionError != null) return (versionError, 0);
      final version = rawVersion as int;
      final rawList = envelope['games'];
      if (rawList is! List) {
        return (
          const StreamCorrupt('Games stream: "games" must be an array.'),
          0,
        );
      }
      final rawGames = List<dynamic>.from(rawList);
      count = rawGames.length;

      if (version > currentStorageVersion) {
        return (
          StreamVersionTooNew(
            streamVersion: version,
            maxSupported: currentStorageVersion,
          ),
          count,
        );
      }

      final migrated = version < currentStorageVersion
          ? runStorageMigrations(rawGames, fromVersion: version)
          : rawGames;
      return (StreamValid(validateMigratedGames(migrated)), count);
    } on ValidationError catch (e) {
      return (StreamCorrupt('Games content invalid: ${e.message}'), count);
    } on Object catch (e) {
      return (StreamCorrupt('Games stream could not be decoded: $e'), count);
    }
  }

  /// Decodes, migrates and validates the settings stream, returning its status.
  static StreamStatus _decodeSettingsStream(
    Archive archive, {
    required bool present,
  }) {
    if (!present) return const StreamNotPresent();

    // As with games: the whole parse → migrate → validate pipeline runs on
    // transit-hash-verified-but-otherwise-untrusted content, so every failure
    // becomes a soft StreamCorrupt instead of an untyped throw escaping decode().
    try {
      var envelope =
          jsonDecode(utf8.decode(archive.findFile('settings.json')!.content))
              as Map<String, dynamic>;
      final rawVersion = envelope['version'];
      final versionError = _streamVersionError(rawVersion, 'Settings');
      if (versionError != null) return versionError;
      final version = rawVersion as int;
      if (version > currentSettingsVersion) {
        return StreamVersionTooNew(
          streamVersion: version,
          maxSupported: currentSettingsVersion,
        );
      }

      if (version < currentSettingsVersion) {
        envelope = runSettingsMigrations(envelope, fromVersion: version);
      }
      validateMigratedSettings(envelope);
      return StreamValid(envelope);
    } on ValidationError catch (e) {
      return StreamCorrupt('Settings content invalid: ${e.message}');
    } on Object catch (e) {
      return StreamCorrupt('Settings stream could not be decoded: $e');
    }
  }

  // Honest raw-input guard: rejects an over-large file before we attempt to
  // decode it. Uses the actual byte length, which cannot be understated.
  static void _checkInputSize(Uint8List zipBytes) {
    if (zipBytes.lengthInBytes > _maxBackupFileBytes) {
      throw const BackupCorrupt(
        'Backup file exceeds the maximum allowed size.',
      );
    }
  }

  // Zip-bomb guard (ARCHITECTURE.md §9). Caps the *actual* decompressed size
  // rather than each entry's attacker-declared `size`: reading `content`
  // decompresses (and caches, so the later read is free) and reports the true
  // length. Caveat: the 10 MB raw-input cap bounds the *compressed* archive,
  // not a single entry's decompressed size — `content` decompresses an entry
  // fully into memory before this running total can reject it, so one crafted
  // entry (deflate ratios reach ~1000:1) could still OOM. Accepted residual:
  // bounding it would need streaming decompression, which `archive` doesn't do.
  static void _checkZipBomb(Archive archive) {
    if (archive.length > _maxArchiveEntries) {
      throw const BackupCorrupt('Archive has too many entries.');
    }
    var totalSize = 0;
    for (final file in archive.files) {
      totalSize += file.content.length;
      if (totalSize > _maxUncompressedBytes) {
        throw const BackupCorrupt('Archive uncompressed size exceeds limit.');
      }
    }
  }
}
