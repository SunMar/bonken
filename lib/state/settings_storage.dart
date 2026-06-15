import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../utils.dart';
import 'settings_migrations.dart';
import 'storage_exceptions.dart';
import 'validation.dart';

/// Raised when the stored settings were written by a newer version of the app.
class UnsupportedSettingsVersionException implements Exception {
  const UnsupportedSettingsVersionException(this.version);

  final int version;

  @override
  String toString() =>
      'Settings were written by a newer version of the app (v$version). '
      'Please update the app.';
}

/// Raised when the stored settings can't be read (corrupt JSON, malformed
/// structure, …). Surfaced to the UI — the user sees an error screen with an
/// option to reset to defaults.
class CorruptSettingsException implements Exception, HasCause {
  const CorruptSettingsException(this.cause);

  @override
  final Object cause;

  @override
  String toString() => 'Settings are corrupt and could not be read: $cause';
}

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

/// All app settings loaded from persistent storage.
final class PersistedSettings {
  const PersistedSettings({
    required this.themeMode,
    required this.defaultStarterVariant,
    required this.defaultHeartsVariant,
  });

  final ThemeMode themeMode;
  final StarterVariant defaultStarterVariant;
  final HeartsVariant defaultHeartsVariant;
}

/// Loads all persisted settings before [runApp].
///
/// When the [settingsStorageKey] key is absent (fresh install or first launch
/// after the migration from flat keys) the legacy flat keys are consumed and
/// the versioned envelope is written back. Unknown or absent values fall back
/// to their enum defaults.
///
/// Throws [UnsupportedSettingsVersionException] when the stored version is
/// newer than [currentSettingsVersion], or [CorruptSettingsException] when the
/// JSON is unreadable.
Future<PersistedSettings> loadPersistedSettings() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    Map<String, dynamic> settings;
    final raw = prefs.getString(settingsStorageKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final version = decoded['version'] as int;
      if (version > currentSettingsVersion) {
        throw UnsupportedSettingsVersionException(version);
      }
      settings = decoded;
      if (version < currentSettingsVersion) {
        settings = runSettingsMigrations(settings, fromVersion: version);
        await prefs.setString(settingsStorageKey, jsonEncode(settings));
      }
    } else {
      // Bootstrap from legacy flat keys (existing installs pre-versioned envelope).
      settings = _buildV1FromLegacyKeys(prefs);
      await prefs.setString(settingsStorageKey, jsonEncode(settings));
      await prefs.remove(_kLegacyThemeModeKey);
      await prefs.remove(_kLegacyStarterVariantKey);
      await prefs.remove(_kLegacyHeartsVariantKey);
    }
    return _parseSettings(settings);
  } on UnsupportedSettingsVersionException {
    rethrow;
  } on Object catch (e) {
    throw CorruptSettingsException(e);
  }
}

/// Read-modify-write helper called by notifiers when a setting changes.
///
/// [section] is `null` for top-level fields (e.g. `'themeMode'`), or a
/// sub-object key (e.g. `'ruleVariants'`) for nested fields.
Future<void> updateSettingsField(
  String? section,
  String key,
  String value,
) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(settingsStorageKey);
  final Map<String, dynamic> settings = raw != null
      ? (jsonDecode(raw) as Map<String, dynamic>)
      : _buildV1Defaults();
  if (section != null) {
    final sub =
        (settings[section] as Map<String, dynamic>?) ?? <String, dynamic>{};
    settings[section] = {...sub, key: value};
  } else {
    settings[key] = value;
  }
  validateMigratedSettings(settings);
  await prefs.setString(settingsStorageKey, jsonEncode(settings));
}

/// Removes the [settingsStorageKey] and any still-present legacy flat keys.
/// Called when the user resets settings from the error screen.
Future<void> clearSettings() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(settingsStorageKey);
  await prefs.remove(_kLegacyThemeModeKey);
  await prefs.remove(_kLegacyStarterVariantKey);
  await prefs.remove(_kLegacyHeartsVariantKey);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _buildV1Defaults() => {
  'version': currentSettingsVersion,
  'themeMode': ThemeMode.system.name,
  'ruleVariants': {
    'starterVariant': StarterVariant.dealerStarts.name,
    'heartsVariant': HeartsVariant.onlyAfterPlayedHeart.name,
  },
};

Map<String, dynamic> _buildV1FromLegacyKeys(SharedPreferences prefs) {
  final themeMode = enumByName(
    ThemeMode.values,
    prefs.getString(_kLegacyThemeModeKey),
    ThemeMode.system,
  );
  final starterVariant = enumByName(
    StarterVariant.values,
    prefs.getString(_kLegacyStarterVariantKey),
    StarterVariant.dealerStarts,
  );
  final heartsVariant = enumByName(
    HeartsVariant.values,
    prefs.getString(_kLegacyHeartsVariantKey),
    HeartsVariant.onlyAfterPlayedHeart,
  );
  return {
    'version': currentSettingsVersion,
    'themeMode': themeMode.name,
    'ruleVariants': {
      'starterVariant': starterVariant.name,
      'heartsVariant': heartsVariant.name,
    },
  };
}

PersistedSettings _parseSettings(Map<String, dynamic> settings) {
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
