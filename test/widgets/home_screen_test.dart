// Tests for [HomeScreen]: the empty placeholder, the saved-games list,
// resuming a session by tapping its card, the card delete + undo flow, and the
// unsupported-storage-version screen.

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/widgets/scoreboard_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

GameSession _session(String id) {
  final players = [for (final n in _names) Player(name: n)];
  return GameSession(
    id: id,
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
}

/// Pumps [HomeScreen] in [container], seeding [saved] sessions first.
Future<void> _pumpHome(
  WidgetTester tester,
  ProviderContainer container, {
  List<GameSession> saved = const [],
}) async {
  await container.read(gameHistoryProvider.future);
  for (final s in saved) {
    await container.read(gameHistoryProvider.notifier).saveGame(s);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpPrefs();

  testWidgets('shows the placeholder when there are no saved games', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container);

    expect(find.text('Nog geen gespeelde spellen'), findsOneWidget);
  });

  testWidgets('renders a card per saved session under the "Spellen" header', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_session('g1')]);

    expect(find.text('Spellen'), findsOneWidget);
    expect(find.byType(ScoreboardCard), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('tapping a card loads the session and opens the GameScreen', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_session('g1')]);

    await tester.tap(find.byType(ScoreboardCard));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(container.read(calculatorProvider).sessionId, 'g1');

    // Drain the autosave debounce scheduled by loadSession.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('deleting a card removes it; snackbar undo restores it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_session('g1')]);

    await tester.tap(find.byTooltip('Verwijderen'));
    await tester.pumpAndSettle();

    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == 'g1'),
      isFalse,
    );
    expect(find.text('Spel verwijderd'), findsOneWidget);
    expect(find.text('Ongedaan maken'), findsOneWidget);

    // Invoke the undo action directly (tapping it also hides the snackbar,
    // which would race the belt-and-suspenders close Timer).
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    action.onPressed();
    await tester.pump();
    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == 'g1'),
      isTrue,
    );

    // Drain the snackbar auto-dismiss Timer + exit animation.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('unsupported storage version shows the update screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'game_history': '{"version":99,"games":[]}',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Let build() reject into AsyncError before the ~200ms Riverpod retry.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('App bijwerken vereist'), findsOneWidget);
    expect(find.text('Geschiedenis wissen'), findsOneWidget);

    // Drain the retry: remove the bad key so the retried build() returns []
    // cleanly, then let the single pending timer fire.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('game_history');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('corrupt storage shows the corrupt-data screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'bonken_game_history': 'this is not json',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Geschiedenis beschadigd'), findsOneWidget);
    expect(find.text('Geschiedenis wissen'), findsOneWidget);

    // Drain the retry (same pattern as the unsupported-version test).
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bonken_game_history');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });
}
