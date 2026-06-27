// Widget tests for [EditGameScreen]. Verifies that:
//   * editing a name + saving propagates the new name to the calculator
//     provider (and pops the screen);
//   * tapping the dropdown to change the dealer shows the dealer
//     warning inline when a game is already in progress;
//   * cancelling with pending changes shows the "discard changes"
//     confirm dialog, and choosing "Verwerpen" pops the screen.

import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/screens/edit_game_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/widgets/amber_warning_box.dart';
import 'package:bonken/widgets/game_name_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<ProviderContainer> _pumpEditPlayers(
  WidgetTester tester, {
  bool gameInProgress = false,
  String? gameName,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(calculatorProvider.notifier);
  notifier.startNewGame(
    players: [for (final name in _names) Player(name: name)],
    dealerIndex: 0,
    gameName: gameName,
  );
  if (gameInProgress) {
    // Select a game then deselect to leave it as a pending (incomplete)
    // game, which flips `_gameInProgress` to true inside the screen.
    notifier.selectGame(const Clubs());
    notifier.deselectGame();
  }

  // Keep the provider alive after EditGameScreen pops (mirrors GameScreen
  // staying in the route stack in production).
  final keepAlive = container.listen<CalculatorState>(
    calculatorProvider,
    (_, _) {},
  );
  addTearDown(keepAlive.close);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditGameScreen()),
    ),
  );
  // Drain the autosave debounce so no Timer survives into teardown.
  // Must be after pumpWidget so the widget subscribes before the autoDispose
  // timer fires.
  await tester.pump(const Duration(milliseconds: 500));
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

      expect(find.byType(EditGameScreen), findsNothing);
      expect(
        (container.read(calculatorProvider) as ActiveSession).playerNames,
        ['Aaron', 'Bob', 'Carol', 'Dan'],
      );
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

      expect(find.byType(EditGameScreen), findsNothing);
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
      expect(find.text('Vul alle spelersnamen in.'), findsOneWidget);
      // Screen did not pop.
      expect(find.byType(EditGameScreen), findsOneWidget);

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
      expect(find.text('Spelersnamen moeten uniek zijn.'), findsOneWidget);
      expect(find.byType(EditGameScreen), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'changing rule variants in the Spelregels sheet commits them on Opslaan',
    (tester) async {
      // Tall surface so the whole bottom sheet (both variant sections) is on
      // screen and its radios are tappable without scrolling.
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await _pumpEditPlayers(tester);

      // Open the rules sheet and switch both variants away from their
      // defaults (dealerStarts / onlyAfterPlayedHeart).
      await tester.tap(find.text('Spelregels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
      await tester.tap(find.text(HeartsVariant.graduatedUnlock.label));
      await tester.pumpAndSettle();

      // Dismiss the sheet, then commit.
      await tester.tap(find.byTooltip('Sluiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();

      expect(find.byType(EditGameScreen), findsNothing);
      final s = container.read(calculatorProvider) as ActiveSession;
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    },
  );

  // The game-name TextField (inside the GameNameField section), distinct from
  // the player-name fields and the dealer dropdown's internal field.
  Finder nameField() => find.descendant(
    of: find.byType(GameNameField),
    matching: find.byType(TextField),
  );

  testWidgets('entering a game name commits it on Opslaan', (tester) async {
    // Tall surface so the (lazily built) game-name field is laid out.
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = await _pumpEditPlayers(tester);

    await tester.enterText(nameField(), 'Avondje kaarten');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
    await tester.pumpAndSettle();

    expect(find.byType(EditGameScreen), findsNothing);
    expect(
      (container.read(calculatorProvider) as ActiveSession).gameName,
      'Avondje kaarten',
    );
  });

  testWidgets('clearing the game name commits null on Opslaan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = await _pumpEditPlayers(tester, gameName: 'Oud potje');
    expect(
      (container.read(calculatorProvider) as ActiveSession).gameName,
      'Oud potje',
    );

    await tester.enterText(nameField(), '');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
    await tester.pumpAndSettle();

    expect(find.byType(EditGameScreen), findsNothing);
    expect(
      (container.read(calculatorProvider) as ActiveSession).gameName,
      isNull,
    );
  });

  group('"Lopend spel wijzigen" in-progress confirm gate', () {
    // Opens the dealer DropdownMenu and picks Bob (slot 1).
    Future<void> changeDealerToBob(WidgetTester tester) async {
      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Bob'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('confirming "Wijzigen" applies the change and pops', (
      tester,
    ) async {
      final container = await _pumpEditPlayers(tester, gameInProgress: true);
      expect(
        (container.read(calculatorProvider) as ActiveSession).firstDealerIndex,
        0,
      );

      await changeDealerToBob(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();

      expect(find.text('Lopend spel wijzigen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Wijzigen'));
      await tester.pumpAndSettle();

      expect(find.byType(EditGameScreen), findsNothing);
      expect(
        (container.read(calculatorProvider) as ActiveSession).firstDealerIndex,
        1,
      );
    });

    testWidgets('declining "Annuleren" aborts the save and stays', (
      tester,
    ) async {
      final container = await _pumpEditPlayers(tester, gameInProgress: true);

      await changeDealerToBob(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();

      expect(find.text('Lopend spel wijzigen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();

      // Dialog dismissed, screen stays, nothing committed.
      expect(find.byType(EditGameScreen), findsOneWidget);
      expect(
        (container.read(calculatorProvider) as ActiveSession).firstDealerIndex,
        0,
      );
    });
  });

  testWidgets(
    'drag-reorder shows the order warning and preserves UUIDs on save',
    (tester) async {
      final container = await _pumpEditPlayers(tester, gameInProgress: true);

      // Capture the original UUID↔name binding before reordering.
      final original =
          (container.read(calculatorProvider) as ActiveSession).players;
      final idByName = {for (final p in original) p.name: p.id};

      // Move Carol (slot 2) to the front.
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(2, 0);
      await tester.pumpAndSettle();

      // The inline player-order warning appears (game in progress + reorder).
      expect(
        find.text('De volgorde van de spelers wordt aangepast.'),
        findsWidgets,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Opslaan'));
      await tester.pumpAndSettle();
      // Mid-game reorder routes through the confirm gate.
      expect(find.text('Lopend spel wijzigen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Wijzigen'));
      await tester.pumpAndSettle();

      expect(find.byType(EditGameScreen), findsNothing);
      final saved =
          (container.read(calculatorProvider) as ActiveSession).players;
      // New seat order is [Carol, Alice, Bob, Dan] …
      expect([for (final p in saved) p.name], ['Carol', 'Alice', 'Bob', 'Dan']);
      // … and every player kept the UUID it entered the screen with.
      for (final p in saved) {
        expect(p.id, idByName[p.name], reason: '${p.name} must keep its UUID');
      }
    },
  );
}
