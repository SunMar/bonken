import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_storage.dart';

/// Default override resolves to [ThemeMode.system]. Override in
/// `ProviderScope.overrides` with `ThemeModeNotifier(initialMode: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedSettings] and `main.dart`.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier({this.initialMode = ThemeMode.system});

  /// Mode the notifier starts in. Pre-loaded from persistent storage in
  /// `main()` and injected via `themeModeProvider.overrideWith(...)`,
  /// which avoids the first-frame flash you'd get from kicking off an
  /// async restore inside [build].
  final ThemeMode initialMode;

  @override
  ThemeMode build() => initialMode;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await updateSettingsField(null, 'themeMode', mode.name);
  }
}
