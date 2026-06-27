import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'models/hearts_variant.dart';
import 'models/starter_variant.dart';
import 'screens/home_screen.dart';
import 'screens/migration_screen.dart';
import 'screens/rules_screen.dart';
import 'services/app_updater.dart';
import 'state/default_hearts_variant_provider.dart';
import 'state/default_starter_variant_provider.dart';
import 'state/settings_storage.dart';
import 'state/theme_mode_provider.dart';
import 'theme/app_theme_extensions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts (Roboto for text, Arimo for the suit glyphs) are bundled as
  // local assets under assets/google_fonts/<version>/ and loaded via the
  // google_fonts package. Runtime fetching is disabled so the app works
  // fully offline.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Pub packages' LICENSE files are auto-registered with [LicenseRegistry],
  // but locally bundled assets are not (Flutter only walks pub dependencies).
  // The root app AGPL LICENSE also surfaces via Flutter's build-time NOTICES.
  registerBundledLicenses();

  // Edge-to-edge: draw behind system bars so users without a visible
  // navigation bar get the full screen.  Each Scaffold body wraps its
  // content in a SafeArea to avoid overlap when bars ARE present.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  // Pre-load persisted settings before the first frame paints to avoid flashes.
  // On error, the app starts with defaults and the home screen shows an error
  // screen from which the user can reset settings.
  PersistedSettings? settings;
  (Object, StackTrace)? settingsLoadError;
  try {
    settings = await loadPersistedSettings();
  } on Object catch (e, st) {
    settingsLoadError = (e, st);
  }

  final packageInfo = await PackageInfo.fromPlatform();
  final isLegacyApp = packageInfo.packageName == 'com.suninet.bonken';

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith(
          () => ThemeModeNotifier(
            initialMode: settings?.themeMode ?? ThemeMode.system,
          ),
        ),
        defaultStarterVariantProvider.overrideWith(
          () => DefaultStarterVariantNotifier(
            initialVariant:
                settings?.defaultStarterVariant ?? StarterVariant.dealerStarts,
          ),
        ),
        defaultHeartsVariantProvider.overrideWith(
          () => DefaultHeartsVariantNotifier(
            initialVariant:
                settings?.defaultHeartsVariant ??
                HeartsVariant.onlyAfterPlayedHeart,
          ),
        ),
        if (settingsLoadError != null)
          settingsLoadErrorProvider.overrideWith(
            () => SettingsLoadErrorNotifier(initialError: settingsLoadError),
          ),
      ],
      child: BonkenApp(isLegacyApp: isLegacyApp),
    ),
  );

  // Fire-and-forget: ask Google Play whether a newer version is available.
  // No-op on web / iOS / sideloaded builds.  Never blocks startup.
  unawaited(checkForAndroidUpdate());
}

class BonkenApp extends ConsumerWidget {
  const BonkenApp({super.key, required this.isLegacyApp});

  final bool isLegacyApp;

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
        extensions: const [
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
        extensions: const [
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
      onGenerateInitialRoutes: (initial) =>
          _generateInitialRoutes(initial, isLegacyApp: isLegacyApp),
    );
  }
}

Route<dynamic>? _generateRoute(RouteSettings settings) {
  final widget = _routeWidgetFor(settings.name);
  if (widget == null) return null;
  return MaterialPageRoute(builder: (_) => widget, settings: settings);
}

List<Route<dynamic>> _generateInitialRoutes(
  String initialRoute, {
  required bool isLegacyApp,
}) {
  final routes = <Route<dynamic>>[
    MaterialPageRoute(
      builder: (_) =>
          isLegacyApp ? const MigrationScreen() : const HomeScreen(),
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

/// Registers LICENSE files for locally bundled fonts that Flutter does not
/// auto-register (only pub package LICENSEs are walked automatically).
///
/// Arimo is registered explicitly so its SIL OFL attribution surfaces in
/// [showLicensePage]. Roboto is Flutter's default font and is already covered
/// by the engine's NOTICES aggregation.
///
/// Exposed for tests so they can verify the entry appears without running
/// [main].
@visibleForTesting
void registerBundledLicenses() {
  _registerBundledLicense(
    'assets/google_fonts/8.1.0/Arimo-LICENSE.txt',
    'Arimo',
  );
}

void _registerBundledLicense(String assetPath, String packageName) {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      packageName,
    ], await rootBundle.loadString(assetPath));
  });
}
