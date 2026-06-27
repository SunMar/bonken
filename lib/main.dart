import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/util/legacy_to_async_migration_util.dart';

import 'screens/boot_error_screen.dart';
import 'screens/home_screen.dart';
import 'screens/migration_screen.dart';
import 'screens/rules_screen.dart';
import 'state/platform_io_providers.dart';
import 'state/settings_provider.dart';
import 'state/settings_storage.dart';
import 'state/theme_mode_provider.dart';
import 'theme/app_theme.dart';

/// Package id of the now-retired app. A build reporting this id is the legacy
/// app and is routed to [MigrationScreen] instead of [HomeScreen] (see §8).
const legacyPackageName = 'com.suninet.bonken';

void main() {
  // Run the whole bootstrap inside a guarded zone so an uncaught async error
  // during startup degrades quietly (§2 "graceful release") instead of taking
  // the process down. The binding is initialized *inside* the zone (next to
  // `runApp`) so framework callbacks run in the same zone — the standard
  // `runZonedGuarded` + Flutter pairing. The zone body is synchronous (it just
  // kicks off `_bootstrap`) so nothing is awaited at the top level.
  runZonedGuarded(() => unawaited(_bootstrap()), _reportUncaughtError);
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorNet();

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

  PersistedSettings? settings;
  (Object, StackTrace)? settingsLoadError;
  bool? isLegacyApp;

  // Move any legacy `SharedPreferences` data into the `SharedPreferencesAsync`
  // backend the storage layer now reads/writes through (DataStore on Android;
  // the same store but un-prefixed keys elsewhere) BEFORE the first async read.
  // If it fails we don't read a half-migrated (possibly empty) store and look
  // like data loss — leave `isLegacyApp` null so [BootErrorScreen] shows and a
  // relaunch retries (the legacy store is left intact; the migration is
  // idempotent).
  if (await migrateLegacyPrefs()) {
    // Pre-load persisted settings before the first frame paints to avoid
    // flashes. On error, the app starts with defaults and the home screen shows
    // an error screen from which the user can reset settings.
    try {
      settings = await loadPersistedSettings();
    } on Object catch (e, st) {
      settingsLoadError = (e, st);
    }

    // Resolve the legacy-vs-new app id before the first frame so the start
    // screen is correct with no flash (PERF: never Home-then-redirect). The
    // signal is load-bearing — it routes legacy users to MigrationScreen — so on
    // failure we must NOT default to either branch (defaulting to "not legacy"
    // would strand a legacy user). Leave `isLegacyApp` null and let [BonkenApp]
    // show [BootErrorScreen]; relaunching re-reads the platform metadata.
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      isLegacyApp = packageInfo.packageName == legacyPackageName;
    } on Object catch (e, st) {
      debugPrint('Failed to read package info at startup: $e\n$st');
    }
  }

  // Own the container explicitly (UncontrolledProviderScope) so the bootstrap
  // can read the Android update-check seam after runApp, just like every other
  // platform side-effect goes through a provider. It lives for the whole app.
  final container = ProviderContainer(
    overrides: [
      // Seed the single in-memory settings blob with the pre-loaded values
      // (or defaults when loading failed; the home screen then surfaces the
      // error). One override replaces the former per-field seeding.
      settingsProvider.overrideWith(
        () => SettingsNotifier(initialSettings: settings),
      ),
      if (settingsLoadError != null)
        settingsLoadErrorProvider.overrideWith(
          () => SettingsLoadErrorNotifier(initialError: settingsLoadError),
        ),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: BonkenApp(isLegacyApp: isLegacyApp),
    ),
  );

  // Fire-and-forget: ask Google Play whether a newer version is available.
  // No-op on web / iOS / sideloaded builds.  Never blocks startup. Routed
  // through the provider seam so it is overridable/no-op-able in tests.
  unawaited(container.read(androidUpdateCheckProvider)());
}

/// Key under which the `SharedPreferencesAsync` store records that the one-off
/// legacy→async data move has run. Kept distinct from every app data key so the
/// migration tool's idempotency flag can never collide with real preferences.
const _prefsMigrationCompletedKey = 'bonken_migrated_to_async_prefs';

/// Moves any legacy `SharedPreferences` data into the `SharedPreferencesAsync`
/// backend the storage layer now uses. Runs on every launch (the package's tool
/// short-circuits once [_prefsMigrationCompletedKey] is set) and leaves the
/// legacy store untouched, so a failure is safe to retry next launch. Returns
/// whether the async store is ready to read — `false` routes to [BootErrorScreen].
///
/// Exposed for tests so the legacy→async data move can be exercised against
/// seeded stored data (the production path also calls it).
@visibleForTesting
Future<bool> migrateLegacyPrefs() async {
  try {
    await migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary(
      legacySharedPreferencesInstance: await SharedPreferences.getInstance(),
      sharedPreferencesAsyncOptions: const SharedPreferencesOptions(),
      migrationCompletedKey: _prefsMigrationCompletedKey,
    );
    return true;
  } on Object catch (e, st) {
    debugPrint('SharedPreferences async migration failed: $e\n$st');
    return false;
  }
}

/// Installs the framework + platform-dispatcher error handlers that, together
/// with the [runZonedGuarded] in [main], form the global error net. Keeps the
/// in-dev red error box (via `presentError`) while ensuring uncaught async
/// errors in release are logged and swallowed rather than crashing the app.
void _installGlobalErrorNet() {
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    _reportUncaughtError(error, stack);
    return true;
  };
}

void _reportUncaughtError(Object error, StackTrace stack) {
  debugPrint('Uncaught error: $error\n$stack');
}

class BonkenApp extends ConsumerWidget {
  const BonkenApp({super.key, required this.isLegacyApp});

  /// `true` → legacy app id (→ [MigrationScreen]); `false` → normal app
  /// (→ [HomeScreen]); `null` → the app id could not be read at startup
  /// (→ [BootErrorScreen]).
  final bool? isLegacyApp;

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
      theme: bonkenLightTheme,
      darkTheme: bonkenDarkTheme,
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
  final widget = routeWidgetFor(settings.name);
  if (widget == null) return null;
  return MaterialPageRoute(builder: (_) => widget, settings: settings);
}

List<Route<dynamic>> _generateInitialRoutes(
  String initialRoute, {
  required bool? isLegacyApp,
}) {
  final routes = <Route<dynamic>>[
    MaterialPageRoute(
      builder: (_) => startScreenFor(isLegacyApp),
      settings: const RouteSettings(name: '/'),
    ),
  ];
  final deep = routeWidgetFor(initialRoute);
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

/// The bottom-of-stack start screen for the given legacy signal: legacy id →
/// [MigrationScreen], normal id → [HomeScreen], and an unresolved id (the
/// `PackageInfo` read threw at startup) → [BootErrorScreen] rather than a
/// fabricated branch. Exposed for tests (pure mapping, no runtime branch added).
@visibleForTesting
Widget startScreenFor(bool? isLegacyApp) => switch (isLegacyApp) {
  null => const BootErrorScreen(),
  true => const MigrationScreen(),
  false => const HomeScreen(),
};

/// Returns the widget for a route name, or `null` to fall back to the start
/// screen.  Recognised routes:
///   `/spelregels`              → full rules document
///   `/spelregels/<gameId>`     → rules for one minigame (`MiniGame.id`)
///
/// Exposed for tests so the deep-link grammar can be asserted without driving a
/// platform initial route (the production path also calls it).
@visibleForTesting
Widget? routeWidgetFor(String? name) {
  if (name == null || name == '/' || name.isEmpty) return null;
  if (name == '/spelregels') return const RulesScreen();
  const prefix = '/spelregels/';
  if (name.startsWith(prefix)) {
    final id = name.substring(prefix.length);
    if (id.isNotEmpty) return RulesScreen(singleGameId: id);
  }
  return null;
}

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
