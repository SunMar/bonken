import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme_extensions.dart';

/// The app's light [ThemeData]. Built once on first read (lazy `final`): the
/// theme is static, so there is no need to rebuild it — and re-resolve the
/// Google Fonts text theme — on every `BonkenApp.build`.
final ThemeData bonkenLightTheme = _bonkenTheme(Brightness.light);

/// The app's dark [ThemeData]. Built once on first read, like [bonkenLightTheme].
final ThemeData bonkenDarkTheme = _bonkenTheme(Brightness.dark);

/// Builds the app theme for [brightness]. Light and dark share the seed,
/// Material 3 flag, Roboto text theme and Symbols action icons; only the
/// brightness-dependent text-theme base and the per-brightness theme
/// extensions differ, so the shared fields live in one place.
ThemeData _bonkenTheme(Brightness brightness) {
  final isDarkMode = brightness == Brightness.dark;
  return ThemeData(
    colorSchemeSeed: Colors.indigo,
    brightness: brightness,
    useMaterial3: true,
    textTheme: isDarkMode
        ? GoogleFonts.robotoTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme,
          )
        : GoogleFonts.robotoTextTheme(),
    actionIconTheme: _symbolsActionIconTheme,
    extensions: [
      isDarkMode ? WarningColors.dark : WarningColors.light,
      isDarkMode ? GameSuitColors.dark : GameSuitColors.light,
      isDarkMode ? DoubleStateColors.dark : DoubleStateColors.light,
      isDarkMode ? ScoreColors.dark : ScoreColors.light,
    ],
  );
}

/// Make every auto-generated `BackButton` / `CloseButton` / drawer button
/// (e.g. the implicit leading on an `AppBar` for a pushed route) use the
/// Material Symbols font instead of the legacy MaterialIcons font, so the
/// app's iconography stays consistent with the explicit `Icon(Symbols.*)`
/// usages elsewhere.
final ActionIconThemeData _symbolsActionIconTheme = ActionIconThemeData(
  backButtonIconBuilder: (_) => const Icon(Symbols.arrow_back),
  closeButtonIconBuilder: (_) => const Icon(Symbols.close),
  drawerButtonIconBuilder: (_) => const Icon(Symbols.menu),
  endDrawerButtonIconBuilder: (_) => const Icon(Symbols.menu),
);
