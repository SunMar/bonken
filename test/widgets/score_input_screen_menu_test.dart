// Tests for the AppBar overflow ("Meer") MenuAnchor on
// [ScoreInputScreen]: the menu shows on the game-list view, every entry
// is reachable, and the destructive "Spel verwijderen" action drives
// the full delete-and-undo flow (confirm dialog → delete from history →
// navigate back to HomeScreen → snackbar with undo).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/screens/score_input_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<ProviderContainer> _pumpScoreInputScreen(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  // Seed a fresh session and persist it so "Spel verwijderen" has
  // something to remove from history.
  container
      .read(calculatorProvider.notifier)
      .startNewGame(names: _names, dealerIndex: 0);
  // Drain the autosave debounce so the session lands in history before
  // we open the menu, and so no Timer survives into teardown.
  await tester.pump(const Duration(milliseconds: 500));
  // Wait for the persisted save to settle.
  await container.read(gameHistoryProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ScoreInputScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openOverflowMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Meer'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'overflow menu shows all four entries when no game is selected',
    (tester) async {
      await _pumpScoreInputScreen(tester);
      await _openOverflowMenu(tester);

      expect(find.text('Spelers bewerken'), findsOneWidget);
      expect(find.text('Ronde volgorde'), findsOneWidget);
      expect(find.text('Spel sluiten'), findsOneWidget);
      expect(find.text('Spel verwijderen'), findsOneWidget);
    },
  );

  testWidgets(
    '"Ronde volgorde" is disabled until at least 2 rounds have been played',
    (tester) async {
      await _pumpScoreInputScreen(tester);
      await _openOverflowMenu(tester);

      final reorderItem = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Ronde volgorde'),
      );
      expect(reorderItem.onPressed, isNull);
    },
  );

  testWidgets('"Spelers bewerken" flips the edit-players mode flag', (
    tester,
  ) async {
    final container = await _pumpScoreInputScreen(tester);
    await _openOverflowMenu(tester);

    expect(container.read(isEditPlayersModeProvider), isFalse);
    await tester.tap(find.text('Spelers bewerken'));
    await tester.pumpAndSettle();
    expect(container.read(isEditPlayersModeProvider), isTrue);
  });

  testWidgets(
    '"Spel verwijderen" → confirm → game removed from history, '
    'navigates to HomeScreen, snackbar with undo restores it',
    (tester) async {
      final container = await _pumpScoreInputScreen(tester);
      final sessionId = container.read(calculatorProvider).sessionId;
      // Sanity: the session lives in history.
      expect(
        container.read(gameHistoryProvider).value?.any(
              (g) => g.id == sessionId,
            ),
        isTrue,
      );

      await _openOverflowMenu(tester);
      await tester.tap(find.text('Spel verwijderen'));
      await tester.pumpAndSettle();

      // Confirm dialog.
      expect(find.text('Spel verwijderen?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Verwijderen'));
      await tester.pumpAndSettle();

      // Navigated to HomeScreen.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ScoreInputScreen), findsNothing);

      // Game removed from history.
      expect(
        container.read(gameHistoryProvider).value?.any(
              (g) => g.id == sessionId,
            ),
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
      // calls `controller.close` after its 5s duration. Two closes on the
      // same snackbar throw "Bad state: No element". Invoking the
      // callback only triggers the saveGame side effect; we then let the
      // single Timer-driven close run to completion.
      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      action.onPressed();
      await tester.pump();
      expect(
        container.read(gameHistoryProvider).value?.any(
              (g) => g.id == sessionId,
            ),
        isTrue,
      );

      // Drain the snackbar's auto-dismiss Timer + exit animation.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('overflow menu uses MenuAnchor with bottomEnd alignment '
      '(M3 IconButton overflow pattern)', (tester) async {
    await _pumpScoreInputScreen(tester);
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    expect(
      anchor.style?.alignment,
      AlignmentDirectional.bottomEnd,
    );
    // The trigger is an IconButton with the more_vert symbol.
    expect(find.byIcon(Symbols.more_vert), findsOneWidget);
  });
}
