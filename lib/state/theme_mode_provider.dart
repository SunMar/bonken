import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModePrefsKey = 'theme_mode';

/// Default override resolves to [ThemeMode.system]. Override in
/// `ProviderScope.overrides` with `ThemeModeNotifier(initialMode: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedThemeMode] and `main.dart`.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier({this.initialMode = ThemeMode.system});

  /// Mode the notifier starts in. Pre-loaded from [SharedPreferences] in
  /// `main()` and injected via `themeModeProvider.overrideWith(...)`,
  /// which avoids the first-frame flash you'd get from kicking off an
  /// async restore inside [build].
  final ThemeMode initialMode;

  @override
  ThemeMode build() => initialMode;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModePrefsKey, mode.name);
  }
}

/// Reads the persisted [ThemeMode] from [SharedPreferences].
///
/// Returns [ThemeMode.system] when no value is stored or the stored value
/// can't be matched against [ThemeMode.values]. Awaited in `main()`
/// before [runApp] so the first frame already paints in the user's
/// chosen theme.
Future<ThemeMode> loadPersistedThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_kThemeModePrefsKey);
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => ThemeMode.system,
  );
}
