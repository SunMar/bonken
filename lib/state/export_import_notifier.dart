import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_version.dart';
import '../models/game_session.dart';
import 'backup_codec.dart';
import 'calculator_provider.dart';
import 'game_history_provider.dart';
import 'migrations.dart';
import 'settings_provider.dart';
import 'settings_storage.dart';

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/// Gathers the persisted stream blobs and encodes them into a backup ZIP.
///
/// This is the effectful half of export: it reads the raw SharedPreferences
/// blobs ([prefs]) — exactly what is stored, so the import path can run the
/// normal migration runners on them — and hands them to the pure
/// [BackupCodec.encode]. Reading raw prefs (rather than the live providers)
/// keeps export working even when a provider failed to load.
///
/// [prefs] and [appVersion] are explicit so tests can inject values without
/// hitting platform channels. [appVersion.version] is `null` for dev builds.
Future<Uint8List> exportBackup({
  required SharedPreferencesAsync prefs,
  required AppVersion appVersion,
  required bool includeGames,
  required bool includeSettings,
}) async {
  assert(includeGames || includeSettings, 'Must include at least one stream.');
  // Fall back to an empty envelope when game_history has never been written
  // (new install, no games yet) so export-with-zero-games still succeeds.
  final gamesJson = includeGames
      ? (await prefs.getString(GameHistoryNotifier.storageKey) ??
            jsonEncode({
              'version': currentStorageVersion,
              'games': <dynamic>[],
            }))
      : null;
  // settings_storage.dart always writes the blob during loadSettings() before
  // runApp(), so this key is present by the time export can be triggered.
  final settingsJson = includeSettings
      ? (await prefs.getString(settingsStorageKey))!
      : null;
  return BackupCodec.encode(
    appVersion: appVersion,
    gamesJson: gamesJson,
    settingsJson: settingsJson,
  );
}

// ---------------------------------------------------------------------------
// Analyze (decode)
// ---------------------------------------------------------------------------

/// Signature of the backup-decode seam: turns raw ZIP [bytes] into a validated
/// [DecodedBackup], or throws a [BackupImportException] on a hard failure.
typedef DecodeBackupFn = Future<DecodedBackup> Function(Uint8List bytes);

/// Seam for the analyze phase of import. [BackupCodec.decode]'s ZIP-inflate +
/// SHA-256 + JSON-parse work runs synchronously on whichever isolate calls it;
/// for a large backup that can jank the UI frame. On the primary native
/// (Android/iOS) targets, production runs it through `Isolate.run`, moving that
/// CPU work to a background isolate — the returned [DecodedBackup] is plain
/// data, so it transfers back across the isolate boundary.
///
/// Web has no `Isolate.spawn`, so `Isolate.run` throws `UnsupportedError`
/// there; the web build therefore decodes inline (the 10 MB input cap keeps
/// that cheap). Without this guard every web import fails at the decode step,
/// surfacing as a spurious "corrupt backup" error. Widget tests override this
/// seam to decode inline regardless: the tester's fake-async clock can't drive
/// a real `Isolate.run`, which would hang.
final decodeBackupProvider = Provider<DecodeBackupFn>(
  (ref) => kIsWeb
      ? BackupCodec.decode
      : (bytes) => Isolate.run(() => BackupCodec.decode(bytes)),
);

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
/// transaction, so this is the residual case validation can't rule out. The
/// fields report what *did* commit so the UI can tell the user precisely which
/// data was and wasn't restored. (A failure with nothing committed is surfaced
/// as the original error, not this.)
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

  /// Commits a previously analyzed backup to live storage (ARCHITECTURE.md §9).
  ///
  /// Consumes the validated objects [BackupCodec.decode] already produced
  /// ([DecodedBackup.games] / [DecodedBackup.settings]) — there is **no**
  /// second decode or validate pass, so what commits is exactly what was
  /// previewed. The caller (the import UI) only offers streams whose
  /// [StreamStatus] is [StreamValid], so a selected stream always carries a
  /// payload; the asserts document that contract.
  ///
  /// The two streams live under separate keys with no cross-key transaction, so
  /// the residual case — a low-level write failure *after* one stream already
  /// committed — is surfaced via [PartialImportException] rather than hidden. A
  /// failure with nothing committed is surfaced as the original error.
  Future<ImportResult> applyImport(
    DecodedBackup backup, {
    required bool importGames,
    required bool importSettings,
  }) async {
    final games = importGames ? backup.games : null;
    final settings = importSettings ? backup.settings : null;
    assert(
      !importGames || games != null,
      'importGames requires a valid (StreamValid) games stream.',
    );
    assert(
      !importSettings || settings != null,
      'importSettings requires a valid (StreamValid) settings stream.',
    );

    var gamesImported = 0;
    var settingsUpdated = false;
    try {
      if (games != null) {
        // Only touch the calculator when replacing games. Await the cancel so
        // it both drops the pending debounced autosave AND joins any in-flight
        // write before replaceAll, so neither can resurrect the about-to-be-
        // replaced session mid-flight (mirrors the delete flow).
        // Defer the reset — which clears the active session — until replaceAll
        // succeeds, so a failed games write leaves the in-progress game intact
        // and the "clean failure" report honest. A settings-only import leaves
        // any in-progress game untouched.
        await ref.read(calculatorProvider.notifier).cancelPendingAutosave();
        await ref.read(gameHistoryProvider.notifier).replaceAll(games);
        // Re-read rather than reuse a captured notifier: the autoDispose
        // calculator may have been disposed during the await (nothing watches
        // it during a no-active-game import), and resetting a fresh NoSession is
        // a harmless no-op — whereas reset()-ing a disposed notifier throws.
        ref.read(calculatorProvider.notifier).reset();
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

  /// Commits a validated settings blob as a single atomic write.
  ///
  /// Projects the (already migrated + validated) map into a typed
  /// [PersistedSettings] and hands it to [SettingsNotifier.replaceAll], which
  /// persists the whole blob in one operation — so the import can't leave
  /// settings half-written. The derived theme/variant providers
  /// update reactively. Setting state directly (rather than `ref.invalidate`)
  /// is required: invalidating would rebuild from the OLD `main()`-time
  /// override and silently drop the import (ARCHITECTURE.md §9).
  Future<void> _applySettings(Map<String, dynamic> settings) async {
    await ref
        .read(settingsProvider.notifier)
        .replaceAll(parsePersistedSettings(settings));
  }
}
