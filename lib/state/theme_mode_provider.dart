import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

/// Read-only view of the active theme mode, derived from [settingsProvider]
/// (the single in-memory settings blob). Write via
/// `settingsProvider.notifier.setThemeMode(...)`.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider.select((s) => s.themeMode)),
);
