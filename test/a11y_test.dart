// Accessibility guideline gates. Each top-level screen is pumped with
// semantics enabled and checked against Flutter's built-in WCAG-derived
// guidelines:
//   • labeledTapTargetGuideline  — every tappable node has a label
//   • androidTapTargetGuideline  — tap targets ≥ 48×48
//   • iOSTapTargetGuideline      — tap targets ≥ 44×44 (kept explicit even
//                                  though both platforms currently pass at
//                                  48dp, so any future iOS-specific divergence
//                                  is caught independently)
//   • textContrastGuideline      — text meets 4.5:1 contrast
// These ride the normal `flutter test` gate (no separate CI step).

import 'dart:convert';
import 'dart:typed_data';

import 'package:bonken/models/app_version.dart';
import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/boot_error_screen.dart';
import 'package:bonken/screens/edit_game_screen.dart';
import 'package:bonken/screens/export_screen.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/screens/import_screen.dart';
import 'package:bonken/screens/migration_screen.dart';
import 'package:bonken/screens/new_game_screen.dart';
import 'package:bonken/screens/qr_display_screen.dart';
import 'package:bonken/screens/qr_scanner_screen.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/screens/rules_screen.dart';
import 'package:bonken/screens/settings_screen.dart';
import 'package:bonken/state/backup_codec.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/export_import_notifier.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/migrations.dart' show currentStorageVersion;
import 'package:bonken/state/platform_io_providers.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/widgets/doubles_picker.dart';
import 'package:bonken/widgets/qr_scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

RoundRecord _dominoesRound(int n, List<Player> players) => RoundRecord(
  roundNumber: n,
  game: const Dominoes(),
  chooserId: players[1].id,
  scoresByPlayer: {
    players[0].id: -100,
    players[1].id: 0,
    players[2].id: 0,
    players[3].id: 0,
  },
  input: RecipientInput([players[0].id]),
  doubles: const DoubleMatrix(),
);

GameSession _session(List<Player> players) => GameSession(
  id: kGameId1,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  scoredAt: DateTime(2024),
  players: players,
  firstDealerId: players[0].id,
  rounds: [_dominoesRound(1, players)],
);

/// A finished (12-round) session with a name — exercises the finished-state UI
/// (the share action in the app bar).
GameSession _finishedSession(List<Player> players) => GameSession(
  id: kGameId1,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  scoredAt: DateTime(2024),
  gameName: 'Kerst 2024',
  players: players,
  firstDealerId: players[0].id,
  rounds: [
    for (int i = 1; i <= GameSession.totalRounds; i++)
      _dominoesRound(i, players),
  ],
);

/// Sets the tall surface the a11y gate runs against (so scrollable screens lay
/// out fully) and restores it on teardown. Shared by [_pump] and the
/// analyzed-import case — which can't use [_pump] (it needs a `ProviderScope`
/// override + a tap) — so the gate's surface size lives in one place.
Future<void> _setGateSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  GameSession? load,
  MiniGame? select,
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await _setGateSurface(tester);
  await container.read(gameHistoryProvider.future);
  if (load != null) {
    await container.read(gameHistoryProvider.notifier).saveGame(load);
    container.read(calculatorProvider.notifier).loadSession(load);
    if (select != null) {
      container.read(calculatorProvider.notifier).selectGame(select);
    }
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500)); // drain autosave
  await tester.pumpAndSettle();
}

Future<void> _expectA11y(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  setUpPrefs();

  testWidgets('HomeScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(tester, const HomeScreen(), load: _session(players));
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('NewGameScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const NewGameScreen());
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('NewGameScreen rules sheet meets a11y guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const NewGameScreen());
    // Open the "Spelregels" bottom sheet — its chrome (header, drag handle,
    // close button) is only built once the card is tapped.
    await tester.tap(find.text('Spelregels'));
    await tester.pumpAndSettle();
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('GameScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(tester, const GameScreen(), load: _session(players));
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('GameScreen (finished) meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    // Finished state surfaces the share action in the app bar.
    await _pump(tester, const GameScreen(), load: _finishedSession(players));
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('QrDisplayScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(
      tester,
      const QrDisplayScreen(),
      load: _session(players),
      overrides: [
        screenBrightnessProvider.overrideWithValue(FakeScreenBrightness()),
      ],
    );
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('QrScannerScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const QrScannerScreen(),
      overrides: [
        qrScannerViewProvider.overrideWithValue(FakeScannerView().builder),
      ],
    );
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('RoundInputScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(
      tester,
      const RoundInputScreen(),
      load: _session(players),
      select: const Duck(),
    );
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets(
    'RoundInputScreen with dimmed force tiles meets a11y guidelines',
    (tester) async {
      final handle = tester.ensureSemantics();
      final players = [for (final n in _names) Player(name: n)];
      await _pump(
        tester,
        const RoundInputScreen(),
        load: _session(players),
        select: const Duck(),
      );
      // After 1 played round the dealer rotates Alice→Bob, so round 2's chooser
      // is Carol (chooser = dealer + 1). Selecting the chooser as initiator
      // turns every target into a dimmed-but-tappable "force" tile AND dims the
      // other initiator tiles — the override + switch-selection states the
      // sweep is meant to cover but the case above never renders. Both now read
      // as disabled (contrast-exempt) with a custom action.
      await tester.tap(
        find
            .descendant(
              of: find.byType(DoublesPicker),
              matching: find.text('Carol'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      // Sanity: a force tile (presented as disabled, with the 'Forceren' custom
      // action) actually rendered, so the guideline sweep below exercises it.
      // Scope to the picker so the bottom scoreboard's "Alice" isn't matched.
      expect(
        tester.getSemantics(
          find
              .descendant(
                of: find.byType(DoublesPicker),
                matching: find.text('Alice'),
              )
              .last,
        ),
        isSemantics(
          isButton: true,
          customActions: const [CustomSemanticsAction(label: 'Forceren')],
        ),
        reason: 'expected the dimmed chooser-initiate force tiles to render',
      );
      await _expectA11y(tester);
      handle.dispose();
    },
  );

  testWidgets('EditGameScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(tester, const EditGameScreen(), load: _session(players));
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('RulesScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const RulesScreen());
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('SettingsScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const SettingsScreen());
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('ImportScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ImportScreen());
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('ImportScreen (analyzed) meets a11y guidelines', (tester) async {
    await _setGateSurface(tester);
    final zip = await _backupZip();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pickBackupBytesProvider.overrideWithValue(() async => zip),
          // Decode inline: the tester's fake-async clock can't drive the
          // production seam's real `Isolate.run`.
          decodeBackupProvider.overrideWithValue(BackupCodec.decode),
        ],
        child: const MaterialApp(home: ImportScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kies bestand'));
    await tester.pumpAndSettle();
    // We are now in the analyzed state with the stream checkboxes shown.
    expect(find.byType(CheckboxListTile), findsWidgets);
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('ExportScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ExportScreen());
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('BootErrorScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const BootErrorScreen());
    await _expectA11y(tester);
    final title = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Bonken kon niet starten'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(title.properties.header, isTrue);
    handle.dispose();
  });

  testWidgets('MigrationScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const MigrationScreen());
    await _expectA11y(tester);
    handle.dispose();
  });
}

/// Builds a valid backup ZIP (one game + settings) for driving [ImportScreen]
/// into its analyzed state in a11y checks.
Future<Uint8List> _backupZip() async {
  final players = [for (final n in _names) Player(name: n)];
  final dt = DateTime(2024);
  final game = GameSession(
    id: kGameId1,
    createdAt: dt,
    updatedAt: dt,
    scoredAt: dt,
    players: players,
    firstDealerId: players[0].id,
    rounds: const [],
  );
  final prefs = SharedPreferencesAsync();
  await prefs.setString(
    GameHistoryNotifier.storageKey,
    jsonEncode({
      'version': currentStorageVersion,
      'games': [game.toJson()],
    }),
  );
  await prefs.setString(
    settingsStorageKey,
    jsonEncode({
      'version': 1,
      'themeMode': 'dark',
      'ruleVariants': {
        'starterVariant': 'dealerStarts',
        'heartsVariant': 'onlyAfterPlayedHeart',
      },
    }),
  );
  return exportBackup(
    prefs: prefs,
    appVersion: const AppVersion(version: '1.0.0', buildNumber: '1'),
    includeGames: true,
    includeSettings: true,
  );
}
