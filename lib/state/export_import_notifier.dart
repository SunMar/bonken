import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_version.dart';
import '../models/game_session.dart';
import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import 'backup_migrations.dart';
import 'calculator_provider.dart';
import 'default_hearts_variant_provider.dart';
import 'default_starter_variant_provider.dart';
import 'game_history_provider.dart';
import 'migrations.dart';
import 'settings_migrations.dart';
import 'settings_storage.dart';
import 'theme_mode_provider.dart';
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

/// Base class for exceptions thrown by [analyzeBackup] on hard structural
/// failures. Hard failures prevent any stream from being processed.
/// Per-stream soft failures (wrong version, corrupt content) are expressed via
/// [StreamStatus] fields on [ImportAnalysis].
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

/// The stream is present, version-compatible, content-valid, and ready to import.
final class StreamValid extends StreamStatus {
  const StreamValid();
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/// Encodes game history and/or settings into a shareable ZIP archive.
///
/// The ZIP contains:
/// - `manifest.json` — metadata, SHA-256 hashes and version info.
/// - `games.json`    — raw versioned SharedPreferences blob (when [includeGames]).
/// - `settings.json` — raw versioned SharedPreferences blob (when [includeSettings]).
///
/// Both blobs are exactly what is stored in SharedPreferences; the import path
/// runs the normal migration runners on them, so no up-front conversion is needed
/// here.
///
/// [prefs] and [appVersion] are explicit so tests can inject values without
/// hitting platform channels. [appVersion.version] is `null` for dev builds.
Future<Uint8List> exportBackup({
  required SharedPreferences prefs,
  required AppVersion appVersion,
  required bool includeGames,
  required bool includeSettings,
}) {
  assert(includeGames || includeSettings, 'Must include at least one stream.');
  return _buildZip(
    prefs: prefs,
    appVersion: appVersion,
    includeGames: includeGames,
    includeSettings: includeSettings,
  );
}

Future<Uint8List> _buildZip({
  required SharedPreferences prefs,
  required AppVersion appVersion,
  required bool includeGames,
  required bool includeSettings,
}) async {
  final archive = Archive();
  final contains = <String>[];
  final hashes = <String, Map<String, String>>{};

  if (includeGames) {
    // Fall back to an empty envelope when game_history has never been written
    // (new install, no games yet) so export-with-zero-games still succeeds.
    final gamesJson =
        prefs.getString(GameHistoryNotifier.storageKey) ??
        jsonEncode({'version': currentStorageVersion, 'games': <dynamic>[]});
    archive.addFile(ArchiveFile.string('games.json', gamesJson));
    hashes['games'] = {
      'algo': 'sha256',
      'hash': sha256.convert(utf8.encode(gamesJson)).toString(),
    };
    contains.add('games');
  }

  if (includeSettings) {
    // settings_storage.dart always writes the blob during loadSettings() before
    // runApp(), so this key is present by the time export can be triggered.
    final settingsJson = prefs.getString(settingsStorageKey)!;
    archive.addFile(ArchiveFile.string('settings.json', settingsJson));
    hashes['settings'] = {
      'algo': 'sha256',
      'hash': sha256.convert(utf8.encode(settingsJson)).toString(),
    };
    contains.add('settings');
  }

  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final utcOffset =
      '$sign'
      '${offset.abs().inHours.toString().padLeft(2, '0')}'
      ':${(offset.abs().inMinutes % 60).toString().padLeft(2, '0')}';
  final manifest = <String, dynamic>{
    'version': currentBackupVersion,
    'appVersion': appVersion.version,
    'buildNumber': appVersion.buildNumber,
    'exportedAt': now.toIso8601String(),
    'utcOffset': utcOffset,
    'contains': contains,
    'hashes': hashes,
  };
  archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));

  return ZipEncoder().encodeBytes(archive);
}

// ---------------------------------------------------------------------------
// Analyze
// ---------------------------------------------------------------------------

/// Summary of a backup file, computed by [analyzeBackup] before any writes.
///
/// [analyzeBackup] throws [BackupImportException] for hard structural failures
/// (unreadable ZIP, missing manifest, hash mismatch, version too new). When it
/// returns, this object describes what the backup contains: each stream's
/// status is expressed as a [StreamStatus] subtype.
class ImportAnalysis {
  const ImportAnalysis({
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

  /// Number of [GameSession] objects in the games stream. Only meaningful
  /// when [gamesStatus] is [StreamValid].
  final int gamesCount;

  /// Whether the backup includes a games stream (present but possibly unimportable).
  bool get hasGames => gamesStatus is! StreamNotPresent;

  /// Whether the backup includes a settings stream (present but possibly unimportable).
  bool get hasSettings => settingsStatus is! StreamNotPresent;

  /// Whether the games stream is ready to import.
  bool get canImportGames => gamesStatus is StreamValid;

  /// Whether the settings stream is ready to import.
  bool get canImportSettings => settingsStatus is StreamValid;
}

/// Reads [zipBytes], validates all contained streams, and returns a summary.
///
/// **No writes are performed.** The result is a preview; [applyImport] runs its
/// own authoritative migrate + validate pass before committing anything.
///
/// Throws [BackupTooNew] when the backup was made by a newer app version.
/// Throws [BackupCorrupt] for any other hard structural failure. Both streams
/// are always fully evaluated — soft per-stream failures (wrong version,
/// corrupt content) are expressed via [ImportAnalysis.gamesStatus] /
/// [ImportAnalysis.settingsStatus], not by throwing.
///
/// Although `async`, the decode + SHA-256 work runs synchronously on the calling
/// isolate (there is no `await` until the first I/O). The 10 MB input cap keeps
/// this cheap; if very large backups ever cause UI jank, move the body to an
/// `Isolate.run` / `compute` — adding a bare `await` would not help, since the
/// CPU-bound work would still execute on the UI isolate.
Future<ImportAnalysis> analyzeBackup(Uint8List zipBytes) async {
  _checkInputSize(zipBytes);
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } on Object catch (e) {
    throw BackupCorrupt('Could not decode ZIP: $e');
  }

  // Zip-bomb / tamper guard (ARCHITECTURE.md §9).
  _checkZipBomb(archive);

  // ── Manifest: decode, migrate, validate ──────────────────────────────────
  // Order mirrors games and settings: version-check → migrate → validate.

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

  // Read version before migration — the runner needs it to know where to
  // start. Structural validation comes after migration so old manifests are
  // brought up to the current schema first.
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

  final appVersion = (manifest['appVersion'] as String?) ?? '';
  final buildNumber = (manifest['buildNumber'] as String?) ?? '';
  final exportedAt = DateTime.parse(manifest['exportedAt'] as String);
  final contains = (manifest['contains'] as List).cast<String>();
  final hashes = manifest['hashes'] as Map<String, dynamic>;

  // ── Integrity check ──────────────────────────────────────────────────────
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
    if (sha256.convert(utf8.encode(content)).toString() != expectedHash) {
      throw BackupCorrupt('Integrity check failed: $key.json hash mismatch.');
    }
  }

  // ── Games stream ─────────────────────────────────────────────────────────
  // File presence and hash already verified; just decode, migrate, validate.

  final StreamStatus gamesStatus;
  var gamesCount = 0;

  if (!contains.contains('games')) {
    gamesStatus = const StreamNotPresent();
  } else {
    final gamesEnvelope =
        jsonDecode(utf8.decode(archive.findFile('games.json')!.content))
            as Map<String, dynamic>;
    final rawGamesVersion = gamesEnvelope['version'];
    if (rawGamesVersion is! int || rawGamesVersion < 1) {
      gamesStatus = const StreamCorrupt(
        'Games stream: "version" must be an integer >= 1.',
      );
    } else {
      final rawGamesList = gamesEnvelope['games'];
      if (rawGamesList is! List) {
        gamesStatus = const StreamCorrupt(
          'Games stream: "games" must be an array.',
        );
      } else {
        final rawGames = List<dynamic>.from(rawGamesList);
        gamesCount = rawGames.length;

        if (rawGamesVersion > currentStorageVersion) {
          gamesStatus = StreamVersionTooNew(
            streamVersion: rawGamesVersion,
            maxSupported: currentStorageVersion,
          );
        } else {
          final migrated = rawGamesVersion < currentStorageVersion
              ? runStorageMigrations(rawGames, fromVersion: rawGamesVersion)
              : rawGames;
          StreamStatus resolved;
          try {
            validateMigratedGames(migrated);
            resolved = const StreamValid();
          } on ValidationError catch (e) {
            resolved = StreamCorrupt('Games content invalid: ${e.message}');
          }
          gamesStatus = resolved;
        }
      }
    }
  }

  // ── Settings stream ──────────────────────────────────────────────────────
  // File presence and hash already verified; just decode, migrate, validate.

  final StreamStatus settingsStatus;

  if (!contains.contains('settings')) {
    settingsStatus = const StreamNotPresent();
  } else {
    var settingsEnvelope =
        jsonDecode(utf8.decode(archive.findFile('settings.json')!.content))
            as Map<String, dynamic>;
    final rawSettingsVersion = settingsEnvelope['version'];
    if (rawSettingsVersion is! int || rawSettingsVersion < 1) {
      settingsStatus = const StreamCorrupt(
        'Settings stream: "version" must be an integer >= 1.',
      );
    } else if (rawSettingsVersion > currentSettingsVersion) {
      settingsStatus = StreamVersionTooNew(
        streamVersion: rawSettingsVersion,
        maxSupported: currentSettingsVersion,
      );
    } else {
      if (rawSettingsVersion < currentSettingsVersion) {
        settingsEnvelope = runSettingsMigrations(
          settingsEnvelope,
          fromVersion: rawSettingsVersion,
        );
      }
      StreamStatus resolved;
      try {
        validateMigratedSettings(settingsEnvelope);
        resolved = const StreamValid();
      } on ValidationError catch (e) {
        resolved = StreamCorrupt('Settings content invalid: ${e.message}');
      }
      settingsStatus = resolved;
    }
  }

  return ImportAnalysis(
    appVersionThatCreatedIt: appVersion,
    buildNumberThatCreatedIt: buildNumber,
    exportedAt: exportedAt,
    gamesStatus: gamesStatus,
    settingsStatus: settingsStatus,
    gamesCount: gamesCount,
  );
}

// Honest raw-input guard: rejects an over-large file before we attempt to
// decode it. Uses the actual byte length, which cannot be understated.
void _checkInputSize(Uint8List zipBytes) {
  if (zipBytes.lengthInBytes > _maxBackupFileBytes) {
    throw const BackupCorrupt('Backup file exceeds the maximum allowed size.');
  }
}

// Zip-bomb guard (ARCHITECTURE.md §9). Called from both [analyzeBackup] and
// [ImportNotifier.applyImport] — see note in §9 on defense-in-depth.
void _checkZipBomb(Archive archive) {
  if (archive.length > _maxArchiveEntries) {
    throw const BackupCorrupt('Archive has too many entries.');
  }
  final totalSize = archive.files.fold<int>(0, (s, f) => s + f.size);
  if (totalSize > _maxUncompressedBytes) {
    throw const BackupCorrupt('Archive uncompressed size exceeds limit.');
  }
}

// ---------------------------------------------------------------------------
// Apply
// ---------------------------------------------------------------------------

/// Outcome of a successful [ImportNotifier.applyImport] call.
class ImportResult {
  const ImportResult({
    required this.gamesImported,
    required this.settingsUpdated,
  });

  /// Number of [GameSession]s written to the game history.
  final int gamesImported;

  /// Whether the settings stream was applied.
  final bool settingsUpdated;
}

/// Thrown by [ImportNotifier.applyImport] when one stream was committed to
/// storage but a later write failed, leaving a **partial** import. The two
/// streams live under separate SharedPreferences keys with no cross-key
/// transaction, so this is the residual case the up-front validation can't
/// rule out. The fields report what *did* commit so the UI can tell the user
/// precisely which data was and wasn't restored. (A failure with nothing
/// committed is surfaced as the original error, not this.)
class PartialImportException implements Exception {
  const PartialImportException({
    required this.gamesImported,
    required this.settingsUpdated,
    required this.cause,
  });

  /// Number of games that were committed before the failure (0 if none).
  final int gamesImported;

  /// Whether settings were committed before the failure.
  final bool settingsUpdated;

  /// The underlying error that interrupted the commit.
  final Object cause;

  @override
  String toString() =>
      'PartialImportException(gamesImported: $gamesImported, '
      'settingsUpdated: $settingsUpdated, cause: $cause)';
}

final importNotifierProvider = NotifierProvider<ImportNotifier, void>(
  ImportNotifier.new,
);

/// Stateless notifier that owns the import commit logic.
///
/// Using a [Notifier] gives the import logic access to [ref] (type [Ref]),
/// which means tests can drive it through [ProviderContainer] without
/// needing a [WidgetRef] (i.e. without a widget tree).
class ImportNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Commits a validated backup to live storage — **all-or-nothing** (ARCHITECTURE.md §9).
  ///
  /// Re-runs migrate + validate as its own authoritative gate before writing
  /// anything. Any [ValidationError] propagates to the caller and leaves
  /// storage untouched. Caller must ensure [analyzeBackup] returned
  /// successfully before calling this.
  Future<ImportResult> applyImport(
    Uint8List zipBytes, {
    required bool importGames,
    required bool importSettings,
  }) async {
    _checkInputSize(zipBytes);
    final archive = ZipDecoder().decodeBytes(zipBytes);
    _checkZipBomb(archive);
    var manifest =
        jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content))
            as Map<String, dynamic>;
    final manifestVersion = manifest['version'] as int;
    if (manifestVersion < currentBackupVersion) {
      manifest = runBackupMigrations((
        manifest: manifest,
        games: null,
        settings: null,
      ), fromVersion: manifestVersion).manifest;
    }
    final contains = (manifest['contains'] as List).cast<String>();

    // ── Phase 1: decode, migrate, validate — NO writes ───────────────────
    // Validating both streams before the first write makes the import
    // all-or-nothing: a failure in either stream leaves storage untouched.
    List<GameSession>? games;
    Map<String, dynamic>? settings;

    if (importGames && contains.contains('games')) {
      final env =
          jsonDecode(utf8.decode(archive.findFile('games.json')!.content))
              as Map<String, dynamic>;
      final fromVersion = env['version'] as int;
      var rawList = List<dynamic>.from(env['games'] as List);
      if (fromVersion < currentStorageVersion) {
        rawList = runStorageMigrations(rawList, fromVersion: fromVersion);
      }
      games = validateMigratedGames(rawList);
    }

    if (importSettings && contains.contains('settings')) {
      var env =
          jsonDecode(utf8.decode(archive.findFile('settings.json')!.content))
              as Map<String, dynamic>;
      final fromVersion = env['version'] as int;
      if (fromVersion < currentSettingsVersion) {
        env = runSettingsMigrations(env, fromVersion: fromVersion);
      }
      validateMigratedSettings(env);
      settings = env;
    }

    // ── Phase 2: commit — both streams valid ─────────────────────────────
    // The two streams live under separate keys with no cross-key transaction,
    // so track what actually committed and surface a partial failure rather
    // than hiding it. Validation already ran in Phase 1, so a throw here is
    // rare (e.g. a low-level storage error mid-commit).
    var gamesImported = 0;
    var settingsUpdated = false;
    try {
      if (games != null) {
        // Only touch the calculator when replacing games: replaceAll overwrites
        // the whole history, so a pending debounced autosave must not resurrect
        // the about-to-be-replaced session (mirrors the delete flow). A
        // settings-only import leaves any in-progress game untouched.
        ref.read(calculatorProvider.notifier)
          ..cancelPendingAutosave()
          ..reset();
        await ref.read(gameHistoryProvider.notifier).replaceAll(games);
        gamesImported = games.length;
      }
      if (settings != null) {
        await _applySettings(settings);
        settingsUpdated = true;
      }
    } on Object catch (e) {
      // Nothing committed yet → a clean failure; surface it normally.
      if (gamesImported == 0 && !settingsUpdated) rethrow;
      throw PartialImportException(
        gamesImported: gamesImported,
        settingsUpdated: settingsUpdated,
        cause: e,
      );
    }

    return ImportResult(
      gamesImported: gamesImported,
      settingsUpdated: settingsUpdated,
    );
  }

  /// Pushes a validated settings blob into the live providers via their setters.
  ///
  /// Do NOT use `ref.invalidate` here: the settings providers are `main()`-time
  /// overrides, so invalidating them rebuilds from the OLD startup value and
  /// silently drops the import (ARCHITECTURE.md §9).
  Future<void> _applySettings(Map<String, dynamic> settings) async {
    await ref
        .read(themeModeProvider.notifier)
        .setMode(ThemeMode.values.byName(settings['themeMode'] as String));
    final variants = settings['ruleVariants'] as Map<String, dynamic>;
    await ref
        .read(defaultStarterVariantProvider.notifier)
        .setValue(
          StarterVariant.values.byName(variants['starterVariant'] as String),
        );
    await ref
        .read(defaultHeartsVariantProvider.notifier)
        .setValue(
          HeartsVariant.values.byName(variants['heartsVariant'] as String),
        );
  }
}
