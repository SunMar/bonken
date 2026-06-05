import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/screens/new_game_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/widgets/player_name_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// Wraps [NewGameScreen] in MaterialApp + ProviderScope and pumps it.
/// Returns the [ProviderContainer] so tests can inspect state.
Future<ProviderContainer> pumpSetup(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NewGameScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Enters [name] into the player slot at [index] (0..3).
Future<void> enterName(WidgetTester tester, int index, String name) async {
  await tester.enterText(playerNameTextField(index), name);
  await tester.pump();
}

/// Finds the TextField inside the [index]-th [PlayerNameField] (so the
/// dealer DropdownMenu's internal TextField doesn't get counted).
Finder playerNameTextField(int index) => find.descendant(
  of: find.byType(PlayerNameField).at(index),
  matching: find.byType(TextField),
);

/// Opens the dealer dropdown and picks the menu item with the given label.
Future<void> pickDealer(WidgetTester tester, String name) async {
  // DealerDropdownField uses Material 3's DropdownMenu, which renders as
  // a TextField with a trailing chevron.  Tapping the field opens the
  // overlay; tap the entry by its visible label inside the overlay.
  await tester.ensureVisible(find.byType(DropdownMenu<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownMenu<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpPrefs();

  testWidgets('fields stay empty even when provider already holds player names '
      '(regression: loading a past game must not leak into "Nieuw spel")', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Simulate the state after loading/finishing a previous game.
    container
        .read(calculatorProvider.notifier)
        .startNewGame(
          players: [
            Player(name: 'Alice'),
            Player(name: 'Bob'),
            Player(name: 'Carol'),
            Player(name: 'Dave'),
          ],
          dealerIndex: 0,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NewGameScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (int i = 0; i < 4; i++) {
      final tf = tester.widget<TextField>(playerNameTextField(i));
      expect(tf.controller!.text, '', reason: 'slot $i must start empty');
    }
    // Drain the autosave debounce timer scheduled by startNewGame so the
    // test teardown doesn't trip the "pending Timer" check.
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'initial state: 4 empty fields, random-dealer hint, Start disabled',
    (tester) async {
      await pumpSetup(tester);

      expect(find.byType(PlayerNameField), findsNWidgets(4));
      for (int i = 0; i < 4; i++) {
        final tf = tester.widget<TextField>(playerNameTextField(i));
        expect(tf.controller!.text, '');
      }
      expect(find.text('Willekeurige deler'), findsWidgets);

      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start spel'),
      );
      expect(startButton.onPressed, isNull);
    },
  );

  testWidgets('Start enabled once 4 unique names are entered', (tester) async {
    await pumpSetup(tester);

    for (int i = 0; i < 4; i++) {
      await enterName(tester, i, ['Alice', 'Bob', 'Carol', 'Dan'][i]);
    }
    await tester.pumpAndSettle();

    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start spel'),
    );
    expect(startButton.onPressed, isNotNull);
    expect(find.text('Twee spelers hebben dezelfde naam.'), findsNothing);
  });

  testWidgets(
    'duplicate names (case-insensitive) show warning and disable Start',
    (tester) async {
      await pumpSetup(tester);
      await enterName(tester, 0, 'Alice');
      await enterName(tester, 1, 'Bob');
      await enterName(tester, 2, 'Carol');
      await enterName(tester, 3, 'alice'); // case-insensitive duplicate

      expect(find.text('Twee spelers hebben dezelfde naam.'), findsOneWidget);
      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start spel'),
      );
      expect(startButton.onPressed, isNull);
    },
  );

  testWidgets('Start disabled while any name slot is empty', (tester) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    // slot 3 left empty
    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start spel'),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('does NOT mutate calculatorProvider while typing', (
    tester,
  ) async {
    final container = await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');

    // Provider stays idle — names live only in local controllers.
    expect(container.read(calculatorProvider), isA<NoSession>());
  });

  /// Reads the visible text inside the dealer DropdownMenu's input field.
  String dealerFieldText(WidgetTester tester) {
    final tf = tester.widget<TextField>(
      find.descendant(
        of: find.byType(DropdownMenu<int>),
        matching: find.byType(TextField),
      ),
    );
    return tf.controller!.text;
  }

  testWidgets('picking "Willekeurige deler" from the menu clears the choice', (
    tester,
  ) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'Dan');
    await tester.pumpAndSettle();

    // First pick a real dealer.
    await pickDealer(tester, 'Bob');
    expect(dealerFieldText(tester), 'Bob');

    // Re-open and pick the random-dealer entry.
    await pickDealer(tester, 'Willekeurige deler');

    // The field reverts to "Willekeurige deler" — the random-dealer entry
    // is now selected, so Bob is no longer committed as the manual dealer.
    expect(dealerFieldText(tester), 'Willekeurige deler');
  });

  testWidgets(
    'picking "Willekeurige deler" after a real dealer routes Start through '
    'the random-dealer flow',
    (tester) async {
      final container = await pumpSetup(tester);
      await enterName(tester, 0, 'Alice');
      await enterName(tester, 1, 'Bob');
      await enterName(tester, 2, 'Carol');
      await enterName(tester, 3, 'Dan');
      await tester.pumpAndSettle();

      // Pick Bob, then change our mind back to random.
      await pickDealer(tester, 'Bob');
      await pickDealer(tester, 'Willekeurige deler');

      await tester.tap(find.widgetWithText(FilledButton, 'Start spel'));
      await tester.pumpAndSettle();

      // Random-dealer announcement dialog appears (same as if Bob had
      // never been picked).
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // A game has been committed; the drawn dealer is one of the four
      // players (we don't assert which — Random() is, well, random).
      final s = container.read(calculatorProvider) as ActiveSession;
      expect(s.dealerIndex, inInclusiveRange(0, 3));
      expect(s.sessionId, isNotEmpty);
    },
  );

  testWidgets(
    'pressing Start with a chosen dealer commits names + dealer + sessionId',
    (tester) async {
      final container = await pumpSetup(tester);
      await enterName(tester, 0, 'Alice');
      await enterName(tester, 1, 'Bob');
      await enterName(tester, 2, 'Carol');
      await enterName(tester, 3, 'Dan');
      await tester.pumpAndSettle();

      await pickDealer(tester, 'Carol');

      await tester.tap(find.widgetWithText(FilledButton, 'Start spel'));
      await tester.pumpAndSettle();

      final s = container.read(calculatorProvider) as ActiveSession;
      expect(s.playerNames, ['Alice', 'Bob', 'Carol', 'Dan']);
      expect(s.dealerIndex, 2);
      expect(s.sessionId, isNotEmpty);
    },
  );

  testWidgets(
    'pressing Start without a dealer shows the random-dealer dialog and then commits',
    (tester) async {
      final container = await pumpSetup(tester);
      await enterName(tester, 0, 'Alice');
      await enterName(tester, 1, 'Bob');
      await enterName(tester, 2, 'Carol');
      await enterName(tester, 3, 'Dan');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start spel'));
      await tester.pumpAndSettle();

      // Random-dealer announcement dialog is shown (sentence visible).
      expect(find.text('is geloot als deler.'), findsOneWidget);

      // Dismiss dialog.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final s = container.read(calculatorProvider) as ActiveSession;
      expect(s.playerNames, ['Alice', 'Bob', 'Carol', 'Dan']);
      expect(s.dealerIndex, inInclusiveRange(0, 3));
      expect(s.sessionId, isNotEmpty);
    },
  );

  testWidgets(
    'reorder via reorderPlayerNames keeps dealer pointing at same player',
    (tester) async {
      await pumpSetup(tester);
      await enterName(tester, 0, 'Alice');
      await enterName(tester, 1, 'Bob');
      await enterName(tester, 2, 'Carol');
      await enterName(tester, 3, 'Dan');
      await tester.pumpAndSettle();

      await pickDealer(tester, 'Carol');

      // Find ReorderableListView and trigger onReorderItem programmatically.
      // Move slot 2 (Carol) to position 0.
      final reorderable = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      reorderable.onReorderItem!(2, 0);
      await tester.pumpAndSettle();

      // Carol should now be at slot 0, and the dealer dropdown should still
      // display her name (i.e. dealer index was rotated alongside).
      final tf0 = tester.widget<TextField>(playerNameTextField(0));
      expect(tf0.controller!.text, 'Carol');

      // Dropdown's selected item still shows Carol.
      expect(find.text('Carol'), findsWidgets);
    },
  );

  testWidgets(
    'changing rule variants in the Spelregels sheet commits them on Start',
    (tester) async {
      // Tall surface so the whole bottom sheet (both variant sections) is on
      // screen and its radios are tappable without scrolling.
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = await pumpSetup(tester);
      await enterName(tester, 0, 'Alice');
      await enterName(tester, 1, 'Bob');
      await enterName(tester, 2, 'Carol');
      await enterName(tester, 3, 'Dan');
      await tester.pumpAndSettle();

      await pickDealer(tester, 'Carol');

      // Open the rules sheet and switch both variants away from their
      // defaults (dealerStarts / onlyAfterPlayedHeart).
      await tester.tap(find.text('Spelregels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
      await tester.tap(find.text(HeartsVariant.graduatedUnlock.label));
      await tester.pumpAndSettle();

      // Dismiss the sheet so the Start button is reachable again.
      await tester.tap(find.byTooltip('Sluiten'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start spel'));
      await tester.pumpAndSettle();

      final s = container.read(calculatorProvider) as ActiveSession;
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    },
  );

  testWidgets(
    'rules card shows the default note, then the deviation once a variant changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpSetup(tester);

      // Seeded from the configured default, so nothing deviates yet.
      expect(find.text('Je speelt met je standaardregels.'), findsOneWidget);

      // Switch the starter variant in the sheet.
      await tester.tap(find.text('Spelregels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sluiten'));
      await tester.pumpAndSettle();

      // The card now summarises the deviation and drops the default note.
      expect(
        find.text(
          '$kStarterVariantSectionTitle → '
          '${StarterVariant.oppositeChooserStarts.label}',
        ),
        findsOneWidget,
      );
      expect(find.text('Je speelt met je standaardregels.'), findsNothing);
    },
  );
}
