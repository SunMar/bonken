import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../utils.dart';
import 'settings_migrations.dart';
import 'storage_exceptions.dart';

/// Public constant for the settings SharedPreferences key, exposed so
/// [home_screen.dart] can read raw data for the error report without depending
/// on internal implementation details.
const String settingsStorageKey = 'settings';

/// Carries the exception and stack trace from a failed [loadPersistedSettings]
/// call. Null on the happy path; non-null when pre-loading failed in `main()`.
///
/// Injected via `ProviderScope.overrides` in `main()`. The home screen watches
/// it and shows a settings-error screen when non-null. Cleared by the
/// "Instellingen wissen" action once settings have been reset.
final settingsLoadErrorProvider =
    NotifierProvider<SettingsLoadErrorNotifier, (Object, StackTrace)?>(
      SettingsLoadErrorNotifier.new,
    );

class SettingsLoadErrorNotifier extends Notifier<(Object, StackTrace)?> {
  SettingsLoadErrorNotifier({this.initialError});

  final (Object, StackTrace)? initialError;

  @override
  (Object, StackTrace)? build() => initialError;

  void clear() => state = null;
}

// Legacy flat keys written before the versioned envelope was introduced.
const String _kLegacyThemeModeKey = 'theme_mode';
const String _kLegacyStarterVariantKey = 'default_starter_variant';
const String _kLegacyHeartsVariantKey = 'default_hearts_variant';

/// All app settings as a single immutable blob.
///
/// This is the in-memory source of truth held by `SettingsNotifier`: every
/// change produces a new instance which is persisted atomically (see
/// [persistSettings]). The fresh-install [PersistedSettings.defaults] values
/// match the per-field fallbacks in [parsePersistedSettings].
final class PersistedSettings {
  const PersistedSettings({
    required this.themeMode,
    required this.defaultStarterVariant,
    required this.defaultHeartsVariant,
  });

  /// The fresh-install defaults, used when nothing has been persisted yet.
  const PersistedSettings.defaults()
    : themeMode = ThemeMode.system,
      defaultStarterVariant = StarterVariant.dealerStarts,
      defaultHeartsVariant = HeartsVariant.onlyAfterPlayedHeart;

  final ThemeMode themeMode;
  final StarterVariant defaultStarterVariant;
  final HeartsVariant defaultHeartsVariant;

  PersistedSettings copyWith({
    ThemeMode? themeMode,
    StarterVariant? defaultStarterVariant,
    HeartsVariant? defaultHeartsVariant,
  }) => PersistedSettings(
    themeMode: themeMode ?? this.themeMode,
    defaultStarterVariant: defaultStarterVariant ?? this.defaultStarterVariant,
    defaultHeartsVariant: defaultHeartsVariant ?? this.defaultHeartsVariant,
  );
}

/// Loads all persisted settings before [runApp].
///
/// When the [settingsStorageKey] key is absent (fresh install or first launch
/// after the migration from flat keys) the legacy flat keys are consumed and
/// the versioned envelope is written back. Unknown or absent values fall back
/// to their enum defaults.
///
/// Throws [UnsupportedVersionException] when the stored version is
/// newer than [currentSettingsVersion], or [CorruptPersistenceException] when the
/// JSON is unreadable.
Future<PersistedSettings> loadPersistedSettings() async {
  final prefs = SharedPreferencesAsync();
  try {
    Map<String, dynamic> settings;
    final raw = await prefs.getString(settingsStorageKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final version = decoded['version'] as int;
      if (version > currentSettingsVersion) {
        throw UnsupportedVersionException(version);
      }
      settings = decoded;
      if (version < currentSettingsVersion) {
        settings = runSettingsMigrations(settings, fromVersion: version);
        await prefs.setString(settingsStorageKey, jsonEncode(settings));
      }
    } else {
      // Bootstrap from legacy flat keys (existing installs pre-versioned
      // envelope). Build the literal-v1 body, then migrate it forward through
      // the chain exactly like any old on-disk blob would be: the genesis
      // builder must stamp the version it actually produces (1), not a moving
      // `currentSettingsVersion`, so a future v2 step reshapes the body instead
      // of it shipping as a v1 shape mislabeled "current".
      settings = runSettingsMigrations(
        _buildV1FromLegacyKeys(
          themeMode: await prefs.getString(_kLegacyThemeModeKey),
          starterVariant: await prefs.getString(_kLegacyStarterVariantKey),
          heartsVariant: await prefs.getString(_kLegacyHeartsVariantKey),
        ),
        fromVersion: 1,
      );
      await prefs.setString(settingsStorageKey, jsonEncode(settings));
      await _removeLegacyKeys(prefs);
    }
    return parsePersistedSettings(settings);
  } on UnsupportedVersionException {
    rethrow;
  } on Object catch (e) {
    throw CorruptPersistenceException(e);
  }
}

/// Persists the full settings blob atomically — a single [SharedPreferences]
/// write of the whole envelope, built from the in-memory [PersistedSettings].
///
/// Replaces the old per-field read-modify-write (`updateSettingsField`): the
/// in-memory `SettingsNotifier` is the single source of truth, so a change
/// rewrites the entire blob from memory and never re-reads or merges the
/// on-disk copy (closes the stale-blob-merge hazard). A multi-field change —
/// notably an import — is therefore one atomic write.
Future<void> persistSettings(PersistedSettings settings) async {
  // Encode first so a serialisation bug surfaces as a bug, not a storage fault.
  final json = jsonEncode(settingsToJson(settings));
  try {
    await SharedPreferencesAsync().setString(settingsStorageKey, json);
  } on Exception catch (e) {
    throw PersistenceWriteException(e);
  }
}

/// Removes the [settingsStorageKey] and any still-present legacy flat keys.
/// Called when the user resets settings from the error screen.
Future<void> clearSettings() async {
  final prefs = SharedPreferencesAsync();
  await prefs.remove(settingsStorageKey);
  await _removeLegacyKeys(prefs);
}

/// Removes the three legacy flat settings keys (the pre-versioned-envelope
/// format). Purged by both the load-bootstrap and [clearSettings]; the keys are
/// frozen historical names, so the set is named in one place.
Future<void> _removeLegacyKeys(SharedPreferencesAsync prefs) async {
  await prefs.remove(_kLegacyThemeModeKey);
  await prefs.remove(_kLegacyStarterVariantKey);
  await prefs.remove(_kLegacyHeartsVariantKey);
}

/// Serialises [settings] into the versioned on-disk envelope.
///
/// Stamps the **current** version because the body is current-shaped by
/// construction (the typed [PersistedSettings] always reflects the latest
/// schema). This is the live-write analogue of `GameHistoryNotifier._persist`,
/// not a frozen genesis body, so the moving-version stamp is correct here.
Map<String, dynamic> settingsToJson(PersistedSettings settings) => {
  'version': currentSettingsVersion,
  'themeMode': settings.themeMode.name,
  'ruleVariants': {
    'starterVariant': settings.defaultStarterVariant.name,
    'heartsVariant': settings.defaultHeartsVariant.name,
  },
};

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Builds the **literal v1** settings body from the (pre-read) legacy flat-key
/// values. Stamps `version: 1` (the version this body actually is), not the
/// moving `currentSettingsVersion` — the caller runs it through
/// `runSettingsMigrations` to reach current, so a future v2 step upgrades it
/// like any old blob. The values are read by the async caller and passed in so
/// this stays a pure, synchronous projection.
Map<String, dynamic> _buildV1FromLegacyKeys({
  required String? themeMode,
  required String? starterVariant,
  required String? heartsVariant,
}) {
  // The app only ever wrote valid enum names to these legacy keys, so a
  // present-but-unknown value is corruption/tampering — strict [enumByName]
  // throws (→ corrupt screen), consistent with [parsePersistedSettings]. An
  // absent key (null) falls back to the default.
  final themeModeValue = enumByName(
    ThemeMode.values,
    themeMode,
    ThemeMode.system,
  );
  final starterValue = enumByName(
    StarterVariant.values,
    starterVariant,
    StarterVariant.dealerStarts,
  );
  final heartsValue = enumByName(
    HeartsVariant.values,
    heartsVariant,
    HeartsVariant.onlyAfterPlayedHeart,
  );
  return {
    'version': 1,
    'themeMode': themeModeValue.name,
    'ruleVariants': {
      'starterVariant': starterValue.name,
      'heartsVariant': heartsValue.name,
    },
  };
}

/// Projects a settings map (already migrated + validated on the import path, or
/// freshly loaded from disk) into the typed [PersistedSettings]. Per-field
/// fallbacks match [PersistedSettings.defaults].
PersistedSettings parsePersistedSettings(Map<String, dynamic> settings) {
  final themeMode = enumByName(
    ThemeMode.values,
    settings['themeMode'] as String?,
    ThemeMode.system,
  );
  final ruleVariants =
      (settings['ruleVariants'] as Map<String, dynamic>?) ?? {};
  final starterVariant = enumByName(
    StarterVariant.values,
    ruleVariants['starterVariant'] as String?,
    StarterVariant.dealerStarts,
  );
  final heartsVariant = enumByName(
    HeartsVariant.values,
    ruleVariants['heartsVariant'] as String?,
    HeartsVariant.onlyAfterPlayedHeart,
  );
  return PersistedSettings(
    themeMode: themeMode,
    defaultStarterVariant: starterVariant,
    defaultHeartsVariant: heartsVariant,
  );
}
