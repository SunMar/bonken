import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import 'settings_storage.dart';

/// Single in-memory source of truth for the app settings blob.
///
/// Holds the whole [PersistedSettings] (theme mode + the two rule-variant
/// defaults) and persists it atomically on every change — one
/// [SharedPreferences] write of the full envelope, mirroring
/// `GameHistoryNotifier`. The per-field [themeModeProvider] /
/// [defaultStarterVariantProvider] / [defaultHeartsVariantProvider] are thin
/// read-only views derived from this provider, so a change rewrites the blob
/// from memory (never a per-field read-modify-write of the on-disk copy).
///
/// The [SettingsNotifier.new] default resolves to [PersistedSettings.defaults].
/// `main()` seeds the loaded value via `settingsProvider.overrideWith(...)` to
/// avoid a first-frame flash — see `loadPersistedSettings`.
final settingsProvider = NotifierProvider<SettingsNotifier, PersistedSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<PersistedSettings> {
  SettingsNotifier({PersistedSettings? initialSettings})
    : _initialSettings = initialSettings ?? const PersistedSettings.defaults();

  /// Value the notifier starts in. Pre-loaded from persistent storage in
  /// `main()` and injected via `settingsProvider.overrideWith(...)`, which
  /// avoids the first-frame flash you'd get from kicking off an async restore
  /// inside [build].
  final PersistedSettings _initialSettings;

  @override
  PersistedSettings build() => _initialSettings;

  Future<void> setThemeMode(ThemeMode mode) =>
      _update(state.copyWith(themeMode: mode));

  Future<void> setDefaultStarterVariant(StarterVariant variant) =>
      _update(state.copyWith(defaultStarterVariant: variant));

  Future<void> setDefaultHeartsVariant(HeartsVariant variant) =>
      _update(state.copyWith(defaultHeartsVariant: variant));

  /// Atomically replaces the entire settings blob. Used by the import path so
  /// all three fields commit in a single write rather than three.
  Future<void> replaceAll(PersistedSettings settings) => _update(settings);

  Future<void> _update(PersistedSettings next) async {
    // Persist first so a failed write leaves in-memory state consistent with
    // storage — no optimistic update that a restart would silently revert.
    await persistSettings(next);
    state = next;
  }
}
