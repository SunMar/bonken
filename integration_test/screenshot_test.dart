import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonken/main.dart' as app;
import 'package:bonken/models/app_version.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/state/backup_codec.dart';
import 'package:bonken/state/export_import_notifier.dart';
import 'package:bonken/widgets/game_input/game_input_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screenshot_fixtures.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screenshot helper
//
// Prints a SCREENSHOT:<name>:<uuid>:<ackPath> marker on stdout so the host-side
// generate_screenshots.dart can capture the full device screen (including the
// system status bar) via `adb exec-out screencap -p` or
// `xcrun simctl io … screenshot`.  After capturing, the host writes the UUID
// to the ack path the test specified; this function polls that file and only
// returns once the ack matches, so the test never advances before the
// screenshot is complete.
// ─────────────────────────────────────────────────────────────────────────────

String _randomHex() {
  final rand = Random.secure();
  return List.generate(
    16,
    (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final uuid = _randomHex();
  final ackPath = Platform.isAndroid
      ? '/data/local/tmp/.screenshot_ack.$name'
      : '/tmp/.screenshot_ack.$name';
  // ignore: avoid_print
  print('SCREENSHOT:$name:$ackPath:$uuid');

  const maxWait = Duration(seconds: 30);
  final deadline = DateTime.now().add(maxWait);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final ack = File(ackPath);
    if (ack.existsSync() && ack.readAsStringSync().trim() == uuid) {
      // Pump until settled: async providers may have completed during the
      // 100ms sleep windows, scheduling one or more frames that need to be
      // rendered before the caller can interact with the widget tree.
      await tester.pumpAndSettle();
      return;
    }
  }
  throw Exception(
    'Screenshot ack timed out for "$name" after ${maxWait.inSeconds}s',
  );
}

// Navigation helpers ──────────────────────────────────────────────────────────

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

// Boots the real app and waits until its [MaterialApp] is mounted.
//
// `app.main()` kicks off an *unawaited* async bootstrap (`_bootstrap`) that
// awaits the legacy→async prefs migration, the settings load and the package
// info before it calls `runApp`. So immediately after `main()` there is a window
// in which no frame is scheduled yet and a bare `pumpAndSettle()` returns on an
// empty tree — the first session reliably loses this race on a cold device,
// leaving [_seedGames] with no MaterialApp to read the container from. Pump
// until the app root has actually mounted before anyone touches the tree.
Future<void> _bootApp(WidgetTester tester) async {
  app.main();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (find.byType(MaterialApp).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw Exception('App did not boot (no MaterialApp mounted) within 30s');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

// Seeds game history by importing [gamesFixture] through the app's real import
// pipeline — the same path a user restoring a backup hits. The fixture JSON is
// encoded to a backup ZIP and run back through [BackupCodec.decode] (so the
// storage migrations execute: a fixture written at an older `version` is brought
// up to the current schema) and [ImportNotifier.applyImport] (which cancels any
// pending autosave before replacing history).
//
// Importing into the *live app's* container sets the in-memory state directly,
// so — unlike writing SharedPreferences before `main()` — it is immune to
// DataStore read caching and to the legacy→async migration racing the first boot
// read (both of which can leave the home screen showing stale or empty data).
Future<void> _seedGames(
  WidgetTester tester,
  Map<String, dynamic> gamesFixture,
) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  final zip = BackupCodec.encode(
    appVersion: const AppVersion(version: '1.0.0', buildNumber: '1'),
    gamesJson: jsonEncode(gamesFixture),
  );
  await container
      .read(importNotifierProvider.notifier)
      .applyImport(
        await BackupCodec.decode(zip),
        importGames: true,
        importSettings: false,
      );
  await tester.pumpAndSettle();
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Start every session from an empty store so the app boots to an empty home
    // screen; each test then seeds its games through the import pipeline (see
    // [_seedGames]). Clearing the async backend (DataStore on Android) also drops
    // the previous session's imported games and the legacy→async migration flag.
    await SharedPreferencesAsync().clear();
  });

  // ==========================================================================
  // Session A — screenshots 01_home, 02_new_game, 07_final_score
  // ==========================================================================
  testWidgets(
    'session A: home, new game, final score',
    (tester) async {
      await _bootApp(tester);
      await _seedGames(tester, sessionAFixture);

      // Screenshot 1: home screen (game B in-progress at top, game A finished below)
      await _screenshot(tester, '01_home');

      // Navigate to the new-game screen
      await tester.tap(find.text('Nieuw spel'));
      await tester.pumpAndSettle();

      // Fill in the four player name fields (first 4 TextField widgets in the form)
      for (final (i, name) in ['Piet', 'Marie', 'Kees', 'Ans'].indexed) {
        await tester.enterText(find.byType(TextField).at(i), name);
        await tester.pumpAndSettle();
      }

      // Dismiss focus so the autocomplete dropdown closes and all form sections
      // are visible before we take the screenshot.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Screenshot 2: new game screen with all four names filled in
      await _screenshot(tester, '02_new_game');

      // Close without saving (X button tooltip is 'Verwerpen'; confirms via dialog)
      await tester.tap(find.byTooltip('Verwerpen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerpen'));
      await tester.pumpAndSettle();

      // Navigate to the completed game (game A, labelled 'Afgerond spel …' in a11y)
      await tester.tap(find.bySemanticsLabel(RegExp('Afgerond spel')));
      await tester.pumpAndSettle();

      // Screenshot 7: final scoreboard (game A is fully played — 12 rounds)
      await _screenshot(tester, '07_final_score');
      await _tapBack(tester);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  // ==========================================================================
  // Session B — screenshots 03–06, 08
  // ==========================================================================
  testWidgets(
    'session B: round inputs and rules',
    (tester) async {
      await _bootApp(tester);
      await _seedGames(tester, sessionBFixture);

      // ----- Screenshot 3: minigame selection (game screen for game C) ----------
      await tester.tap(find.text('Avondje bonken'));
      await tester.pumpAndSettle();
      await _screenshot(tester, '03_minigame_selection');
      await _tapBack(tester);

      // ----- Screenshot 4: doubles/redoubles input (game D) --------------------
      // Fixture: Marie doubled Kees (state=doubled, initiator=Marie).
      // We select Kees as the initiator and press "Slappe hap" to get:
      //   • Marie–Kees → redoubled (Kees goes back on Marie's double)
      //   • Kees–Ans  → doubled
      //   • "Slappe hap" bulk button → filled
      await tester.tap(find.text('Dubbelen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heren / Boeren'));
      await tester.pumpAndSettle();

      // Scroll the doubles card ("Dubbels" header) to the top of the screen.
      await tester.ensureVisible(find.text('Dubbels'));
      await tester.pumpAndSettle();

      // Select Kees as the initiator (first occurrence = the initiator-list tile).
      await tester.tap(find.text('Kees').first);
      await tester.pumpAndSettle();

      // Press the "Slappe hap" OutlinedButton (the bulk-action button, not the
      // player tile — distinguished here by its widget type before it's applied).
      await tester.tap(find.widgetWithText(OutlinedButton, 'Slappe hap'));
      await tester.pumpAndSettle();

      await _screenshot(tester, '04_doubles');
      await _tapBack(tester); // back to game screen (exitPendingRound)
      await _tapBack(tester); // back to home

      // ----- Screenshot 5: 7e / 13e input (game E) -----------------------------
      await tester.tap(find.text('Zeventje'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7e / 13e'));
      await tester.pumpAndSettle();

      // Scroll the count-input card into view.
      // Specify the scrollable inside RoundInputScreen to avoid ambiguity with
      // other ListViews in the navigator stack (home, game screen, etc.).
      final roundInputScrollable = find
          .descendant(
            of: find.byType(RoundInputScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(GameInputForm),
        100,
        scrollable: roundInputScrollable,
      );
      await tester.pumpAndSettle();

      await _screenshot(tester, '05_seventh_thirteenth');
      await _tapBack(tester); // back to game screen
      await _tapBack(tester); // back to home

      // ----- Screenshot 6: Zonder troef input (game F) -------------------------
      await tester.tap(find.text('Troefje'));
      await tester.pumpAndSettle();
      // 'Zonder troef' is the last positive tile — scroll until it's built.
      // Specify the GameScreen scrollable to avoid matching the HomeScreen
      // ListView that's still alive in the navigator stack below.
      // After scrollUntilVisible, ensureVisible(alignment: 0.5) centers the
      // tile in the viewport; without it, on tablet the tile lands exactly at
      // the bottom clipping boundary and the tap misses on CI.
      await tester.scrollUntilVisible(
        find.text('Zonder troef'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(GameScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Zonder troef')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.text('Zonder troef'));
      await tester.pumpAndSettle();

      // Scroll the count-input card into view.
      final roundInputScrollable2 = find
          .descendant(
            of: find.byType(RoundInputScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(GameInputForm),
        100,
        scrollable: roundInputScrollable2,
      );
      await tester.pumpAndSettle();

      await _screenshot(tester, '06_no_trump');
      await _tapBack(tester);
      await _tapBack(tester);

      // ----- Screenshot 8: Spelregels (rules screen, top of page) --------------
      await tester.tap(find.byTooltip('Spelregels'));
      await tester.pumpAndSettle();
      await _screenshot(tester, '08_rules');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
