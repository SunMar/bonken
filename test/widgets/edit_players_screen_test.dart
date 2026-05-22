// Widget tests for [EditPlayersScreen]. Verifies that:
//   * editing a name + saving propagates the new name to the calculator
//     provider (and pops the screen);
//   * tapping the dropdown to change the dealer shows the dealer
//     warning inline when a game is already in progress;
//   * cancelling with pending changes shows the "discard changes"
//     confirm dialog, and choosing "Verwerpen" pops the screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/screens/edit_players_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/widgets/amber_warning_box.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<ProviderContainer> _pumpEditPlayers(
  WidgetTester tester, {
  bool gameInProgress = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(calculatorProvider.notifier);
  notifier.startNewGame(
    players: [for (final name in _names) Player(name: name)],
    dealerIndex: 0,
  );
  if (gameInProgress) {
    // Select a game then deselect to leave it as a pending (incomplete)
    // game, which flips `_gameInProgress` to true inside the screen.
    notifier.selectGame(const Clubs());
    notifier.deselectGame();
  }
  // Drain the autosave debounce so no Timer survives into teardown.
  await tester.pump(const Duration(milliseconds: 500));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditPlayersScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  initializeWidgets();
  setUpPrefs();

  testWidgets(
    'editing a name and tapping "Opslaan" propagates to the provider',
    (tester) async {
      final container = await _pumpEditPlayers(tester);

      // Edit Alice → Aaron.
      await tester.enterText(find.byType(TextField).first, 'Aaron');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();

      expect(find.byType(EditPlayersScreen), findsNothing);
      expect(container.read(calculatorProvider).playerNames, [
        'Aaron',
        'Bob',
        'Carol',
        'Dan',
      ]);
    },
  );

  testWidgets(
    'changing the dealer with a game in progress shows the inline dealer warning',
    (tester) async {
      await _pumpEditPlayers(tester, gameInProgress: true);

      // No warning initially.
      expect(find.byType(AmberWarningBox), findsNothing);

      // Open the dealer DropdownMenu and pick Bob.
      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Bob'),
        ),
      );
      await tester.pumpAndSettle();

      // The inline dealer warning should now be visible.
      expect(
        find.text('De deler van de eerste ronde wordt aangepast.'),
        findsOneWidget,
      );
      expect(find.byType(AmberWarningBox), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling with unsaved changes shows the discard confirm dialog',
    (tester) async {
      await _pumpEditPlayers(tester);

      await tester.enterText(find.byType(TextField).first, 'Aaron');
      await tester.pumpAndSettle();

      // Tap the leading "Verwerpen" close icon button.
      await tester.tap(find.byTooltip('Verwerpen'));
      await tester.pumpAndSettle();

      expect(find.text('Wijzigingen verwerpen'), findsOneWidget);
      expect(find.text('Je wijzigingen gaan verloren.'), findsOneWidget);

      // Confirm the discard (the dialog button, not the AppBar action).
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Verwerpen'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EditPlayersScreen), findsNothing);
    },
  );

  testWidgets(
    'tapping Opslaan with an empty name shows the incomplete-form snackbar',
    (tester) async {
      await _pumpEditPlayers(tester);

      // Clear Alice's name.
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Vul alle spelersnamen in'), findsOneWidget);
      // Screen did not pop.
      expect(find.byType(EditPlayersScreen), findsOneWidget);

      // Drain the snackbar timer so no Timer survives into teardown.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'tapping Opslaan with duplicate names shows the uniqueness snackbar',
    (tester) async {
      await _pumpEditPlayers(tester);

      // Make Bob a (case-insensitive) duplicate of Alice.
      await tester.enterText(find.byType(TextField).at(1), 'alice');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Spelersnamen moeten uniek zijn'), findsOneWidget);
      expect(find.byType(EditPlayersScreen), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    },
  );
}
