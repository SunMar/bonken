import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'screens/rules_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_updater.dart';
import 'state/theme_mode_provider.dart';
import 'theme/app_theme_extensions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts are bundled as local assets (assets/google_fonts/<version>/).
  // Runtime fetching is disabled so the app works fully offline.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Pub packages' LICENSE files are auto-registered with the
  // [LicenseRegistry], but locally bundled assets are not (Flutter only
  // walks pub dependencies). Register them explicitly so they surface in
  // `showLicensePage()` — the Bitstream Vera + DejaVu addendum requires
  // the copyright notices to be reachable wherever the font is
  // redistributed. The root app's own AGPL LICENSE is surfaced via
  // Flutter's build-time NOTICES aggregation (not registered here).
  registerBundledLicenses();

  // Edge-to-edge: draw behind system bars so users without a visible
  // navigation bar get the full screen.  Each Scaffold body wraps its
  // content in a SafeArea to avoid overlap when bars ARE present.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  // Pre-load the persisted theme mode before the first frame paints so
  // the app doesn't flash the system theme on cold start when the user
  // has chosen a specific light/dark override.
  final initialThemeMode = await loadPersistedThemeMode();

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith(
          () => ThemeModeNotifier(initialMode: initialThemeMode),
        ),
      ],
      child: const BonkenApp(),
    ),
  );

  // Fire-and-forget: ask Google Play whether a newer version is available.
  // No-op on web / iOS / sideloaded builds.  Never blocks startup.
  unawaited(checkForAndroidUpdate());
}

/// Registers LICENSE files for assets that Flutter does not auto-register
/// (locally bundled fonts). The root app's AGPL LICENSE surfaces via
/// Flutter's build-time NOTICES aggregation instead.
///
/// Exposed for tests so they can verify the entries appear without
/// running [main].
@visibleForTesting
void registerBundledLicenses() {
  _registerBundledLicense('assets/dejavu/2.37/LICENSE', 'DejaVu Sans');
}

void _registerBundledLicense(String assetPath, String packageName) {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      packageName,
    ], await rootBundle.loadString(assetPath));
  });
}

class BonkenApp extends ConsumerWidget {
  const BonkenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Bonken',
      debugShowCheckedModeBanner: false,
      // Force Dutch UI regardless of the user's system/browser language.
      locale: const Locale('nl'),
      supportedLocales: const [Locale('nl')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(),
        actionIconTheme: _symbolsActionIconTheme,
        extensions: [
          WarningColors.light,
          GameSuitColors.standard,
          DoubleStateColors.light,
          ScoreColors.light,
        ],
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        actionIconTheme: _symbolsActionIconTheme,
        extensions: [
          WarningColors.dark,
          GameSuitColors.standard,
          DoubleStateColors.dark,
          ScoreColors.dark,
        ],
      ),
      themeMode: themeMode,
      // Routing: the start screen is always the bottom of the stack.
      // Deep links like `/spelregels` or `/spelregels/dominoes` push the
      // matching rules page on top of it, so the back button returns to
      // the start screen instead of leaving the app.
      onGenerateRoute: _generateRoute,
      onGenerateInitialRoutes: _generateInitialRoutes,
    );
  }
}

Route<dynamic>? _generateRoute(RouteSettings settings) {
  final widget = _routeWidgetFor(settings.name);
  if (widget == null) return null;
  return MaterialPageRoute(builder: (_) => widget, settings: settings);
}

List<Route<dynamic>> _generateInitialRoutes(String initialRoute) {
  final routes = <Route<dynamic>>[
    MaterialPageRoute(
      builder: (_) => const HomeScreen(),
      settings: const RouteSettings(name: '/'),
    ),
  ];
  final deep = _routeWidgetFor(initialRoute);
  if (deep != null && initialRoute != '/') {
    routes.add(
      MaterialPageRoute(
        builder: (_) => deep,
        settings: RouteSettings(name: initialRoute),
      ),
    );
  }
  return routes;
}

/// Returns the widget for a route name, or `null` to fall back to the start
/// screen.  Recognised routes:
///   `/spelregels`              → full rules document
///   `/spelregels/<gameId>`     → rules for one minigame (`MiniGame.id`)
Widget? _routeWidgetFor(String? name) {
  if (name == null || name == '/' || name.isEmpty) return null;
  if (name == '/spelregels') return const RulesScreen();
  const prefix = '/spelregels/';
  if (name.startsWith(prefix)) {
    final id = name.substring(prefix.length);
    if (id.isNotEmpty) return RulesScreen(singleGameId: id);
  }
  return null;
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
