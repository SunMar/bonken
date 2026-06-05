// Tests for the in-game [_LiveScoreboard] header actions on
// [GameScreen]: the "Spel bewerken" icon pushes [EditGameScreen],
// and the destructive "Spel verwijderen" action drives the full
// delete-and-undo flow (confirm dialog → delete from history →
// navigate back to HomeScreen → snackbar with undo).
//
// The reusable AppBar building blocks (Spelregels icon, Thema menu,
// About dialog) are exercised by `app_bar_widgets_test.dart`; this
// file focuses on what is unique to the game screen.

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/edit_game_screen.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/widgets/scoreboard_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<ProviderContainer> _pumpGameScreen(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  // Seed a session with one completed round so the history list renders
  // and the scoreboard shows realistic non-zero scores.
  final players = [for (final name in _names) Player(name: name)];
  final session = GameSession(
    id: 'seed-session',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    players: players,
    firstDealerId: players[0].id,
    rounds: [
      RoundRecord(
        roundNumber: 1,
        game: const Dominoes(),
        chooserId: players[1].id,
        scoresByPlayer: {
          players[0].id: 10,
          players[1].id: -10,
          players[2].id: 5,
          players[3].id: -5,
        },
        input: const RecipientInput([null]),
        doubles: const DoubleMatrix(),
      ),
    ],
  );
  await container.read(gameHistoryProvider.future);
  await container.read(gameHistoryProvider.notifier).saveGame(session);

  // Start from HomeScreen so the navigator stack is [HomeScreen, GameScreen].
  // This mirrors the real app flow and lets _deleteGame pop() back correctly.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ScoreboardCard));
  await tester.pumpAndSettle();
  // Drain the autosave debounce timer scheduled by loadSession.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpPrefs();

  testWidgets('AppBar has Spelregels icon and no overflow / theme icon', (
    tester,
  ) async {
    await _pumpGameScreen(tester);
    expect(find.byTooltip('Meer'), findsNothing);
    expect(find.byIcon(Symbols.more_vert), findsNothing);
    expect(find.byTooltip('Spelregels'), findsOneWidget);
    // Thema icon only lives on the home screen.
    expect(find.byTooltip('Thema'), findsNothing);
  });

  testWidgets(
    'live scoreboard header shows Spel bewerken + Verwijderen icons',
    (tester) async {
      await _pumpGameScreen(tester);
      expect(find.byTooltip('Spel bewerken'), findsOneWidget);
      expect(find.byTooltip('Spel verwijderen'), findsOneWidget);
    },
  );

  testWidgets('"Spel bewerken" pushes the EditGameScreen', (tester) async {
    await _pumpGameScreen(tester);
    expect(find.byType(EditGameScreen), findsNothing);
    await tester.tap(find.byTooltip('Spel bewerken'));
    await tester.pumpAndSettle();
    expect(find.byType(EditGameScreen), findsOneWidget);
  });

  testWidgets('"Spel verwijderen" → confirm → game removed from history, '
      'navigates to HomeScreen, snackbar with undo restores it', (
    tester,
  ) async {
    final container = await _pumpGameScreen(tester);
    final sessionId =
        (container.read(calculatorProvider) as ActiveSession).sessionId;
    // Sanity: the session lives in history.
    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == sessionId),
      isTrue,
    );

    await tester.tap(find.byTooltip('Spel verwijderen'));
    await tester.pumpAndSettle();

    // Confirm dialog.
    expect(find.text('Spel verwijderen'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Verwijderen'));
    await tester.pumpAndSettle();

    // Navigated to HomeScreen.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    // Game removed from history.
    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == sessionId),
      isFalse,
    );

    // Snackbar with undo action.
    expect(find.text('Spel verwijderd'), findsOneWidget);
    expect(find.text('Ongedaan maken'), findsOneWidget);

    // Tapping "Ongedaan maken" re-saves the deleted session. We invoke
    // the action callback directly (rather than tapping the widget) so
    // we don't double-close the snackbar — `SnackBarAction` calls
    // `hideCurrentSnackBar` on tap, while the snackbar's
    // belt-and-suspenders `Timer` (in `showGameDeletedSnackBar`) also
    // calls `controller.close` after its 5s duration.
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    action.onPressed();
    await tester.pump();
    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == sessionId),
      isTrue,
    );

    // Drain the snackbar's auto-dismiss Timer + exit animation.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
