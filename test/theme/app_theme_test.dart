import 'package:bonken/theme/app_theme.dart';
import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The themes build a GoogleFonts text theme, which touches the asset
  // binding — initialize it for these plain (non-widget) tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Characterizes the shared _bonkenTheme builder: each brightness must wire
  // its own brightness-appropriate extensions.
  test('light theme carries the light extensions', () {
    final theme = bonkenLightTheme;
    expect(theme.brightness, Brightness.light);
    expect(theme.extension<ScoreColors>(), ScoreColors.light);
    expect(theme.extension<WarningColors>(), WarningColors.light);
    expect(theme.extension<DoubleStateColors>(), DoubleStateColors.light);
    expect(theme.extension<GameSuitColors>(), GameSuitColors.light);
  });

  test('dark theme carries the dark extensions', () {
    final theme = bonkenDarkTheme;
    expect(theme.brightness, Brightness.dark);
    expect(theme.extension<ScoreColors>(), ScoreColors.dark);
    expect(theme.extension<WarningColors>(), WarningColors.dark);
    expect(theme.extension<DoubleStateColors>(), DoubleStateColors.dark);
    expect(theme.extension<GameSuitColors>(), GameSuitColors.dark);
  });
}
