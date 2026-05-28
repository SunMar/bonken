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

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/edit_players_screen.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/screens/new_game_screen.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/screens/rules_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

GameSession _session(List<Player> players) => GameSession(
  id: 'seed',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  players: players,
  firstDealerId: players[0].id,
  rounds: [
    RoundRecord(
      roundNumber: 1,
      game: const Dominoes(),
      chooserId: players[1].id,
      scoresByPlayer: {for (final p in players) p.id: 0},
      input: const {},
      doubles: const DoubleMatrix(),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  GameSession? load,
  MiniGame? select,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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

  testWidgets('GameScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(tester, const GameScreen(), load: _session(players));
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

  testWidgets('EditPlayersScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final players = [for (final n in _names) Player(name: n)];
    await _pump(tester, const EditPlayersScreen(), load: _session(players));
    await _expectA11y(tester);
    handle.dispose();
  });

  testWidgets('RulesScreen meets a11y guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const RulesScreen());
    await _expectA11y(tester);
    handle.dispose();
  });
}
