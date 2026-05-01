import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/start_screen.dart';
import 'services/app_updater.dart';
import 'state/theme_mode_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts are bundled as local assets (assets/google_fonts/8.1.0/).
  // Runtime fetching is disabled so the app works fully offline.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Edge-to-edge: draw behind system bars so users without a visible
  // navigation bar get the full screen.  Each Scaffold body wraps its
  // content in a SafeArea to avoid overlap when bars ARE present.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ProviderScope(child: BonkenApp()));

  // Fire-and-forget: ask Google Play whether a newer version is available.
  // No-op on web / iOS / sideloaded builds.  Never blocks startup.
  unawaited(checkForAndroidUpdate());
}

class BonkenApp extends ConsumerWidget {
  const BonkenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Bonken',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      themeMode: themeMode,
      home: const StartScreen(),
    );
  }
}
