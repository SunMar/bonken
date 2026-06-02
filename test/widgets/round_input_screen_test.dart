// Widget tests for [RoundInputScreen]. Covers the discard-changes
// confirmation flow on back-navigation and the chooser-selector
// behaviour (immediate apply for the default chooser, confirm dialog
// for any other player).

import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

List<Player> _makePlayers() => [for (final name in _names) Player(name: name)];

Widget _wrapWithNavigator(ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RoundInputScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<ProviderContainer> _pumpRoundInput(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(calculatorProvider.notifier);
  notifier.startNewGame(players: _makePlayers(), dealerIndex: 0);
  notifier.selectGame(const Clubs());
  // Drain the autosave debounce so no Timer survives into teardown.
  await tester.pump(const Duration(milliseconds: 500));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RoundInputScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  initializeWidgets();
  setUpPrefs();

  testWidgets(
    'changing the chooser to the default (dealer+1) updates state without a dialog',
    (tester) async {
      final container = await _pumpRoundInput(tester);
      // dealerIndex 0 → default chooser is index 1 (Bob), which is the
      // initial chooserIndex. Move it to Carol (index 2) via the
      // underlying notifier so the "back to default" path becomes
      // the one under test.
      container.read(calculatorProvider.notifier).setChooser(2);
      await tester.pumpAndSettle();
      expect(container.read(calculatorProvider).chooserIndex, 2);

      // Open the chooser DropdownMenu (the only DropdownMenu<int> on
      // this screen) and pick Bob (the default, dealer+1).
      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Bob'),
        ),
      );
      await tester.pumpAndSettle();

      // No confirm dialog appears.
      expect(find.text('Kiezer wijzigen'), findsNothing);
      expect(container.read(calculatorProvider).chooserIndex, 1);
      // Drain autosave debounce so no Timer survives into teardown.
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'changing the chooser to a non-default player asks for confirmation',
    (tester) async {
      final container = await _pumpRoundInput(tester);
      // dealer 0 → default chooser Bob (1). Pick Dan (3) instead.
      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Dan'),
        ),
      );
      await tester.pumpAndSettle();

      // Confirm dialog should appear; cancelling keeps chooserIndex.
      expect(find.text('Kiezer wijzigen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();
      expect(container.read(calculatorProvider).chooserIndex, 1);

      // Try again and confirm.
      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Dan'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Instellen'));
      await tester.pumpAndSettle();
      expect(container.read(calculatorProvider).chooserIndex, 3);
      // Drain autosave debounce so no Timer survives into teardown.
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'tapping Opslaan while editing a non-last round with incomplete input shows the snackbar',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.startNewGame(players: _makePlayers(), dealerIndex: 0);
      final ps = container.read(calculatorProvider).players;

      // Round 1 — Clubs, valid input, commit.
      notifier.selectGame(const Clubs());
      notifier.updateInput(
        CountsInput({ps[0].id: 4, ps[1].id: 4, ps[2].id: 2, ps[3].id: 3}),
      );
      notifier.deselectGame();
      // Round 2 — Diamonds, valid input, commit. Now there are two
      // rounds in history, so editing round 1 is a non-last-round edit.
      notifier.selectGame(const Diamonds());
      notifier.updateInput(
        CountsInput({ps[0].id: 4, ps[1].id: 3, ps[2].id: 5, ps[3].id: 1}),
      );
      notifier.deselectGame();

      // Restore round 1 for edit, then make its input invalid.
      final round1 = container.read(calculatorProvider).history.first;
      notifier.restoreRound(round1);
      notifier.updateInput(
        CountsInput({ps[0].id: 4, ps[1].id: 3, ps[2].id: 2, ps[3].id: 0}),
      ); // sum 9 ≠ 13
      expect(
        container.read(calculatorProvider).inputState,
        isNot(InputState.complete),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RoundInputScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Opslaan looks disabled (onPressed null), but tapping still shows the
      // snackbar via the GestureDetector overlay.
      final opslaan = find.widgetWithText(FilledButton, 'Opslaan');
      expect(tester.widget<FilledButton>(opslaan).onPressed, isNull);
      await tester.tap(opslaan, warnIfMissed: false);
      await tester.pump(); // schedule snackbar
      await tester.pump(const Duration(milliseconds: 100)); // animate in

      // Snackbar appears with the expected text; no modal dialog.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Vul de score volledig in om op te slaan'),
        findsOneWidget,
      );
      expect(find.text('Score niet compleet'), findsNothing);

      // Drain the snackbar timer + autosave debounce so no Timer
      // survives into teardown.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'back on a pending round preserves the pending stash with latest input',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.startNewGame(players: _makePlayers(), dealerIndex: 0);
      final ps = container.read(calculatorProvider).players;
      notifier.selectGame(const Clubs());
      notifier.updateInput(
        CountsInput({ps[0].id: 3, ps[1].id: 2, ps[2].id: 0, ps[3].id: 0}),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(_wrapWithNavigator(container));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Terug'));
      await tester.pumpAndSettle();

      expect(find.byType(RoundInputScreen), findsNothing);
      final s = container.read(calculatorProvider);
      expect(s.hasPendingGame, isTrue);
      final p = s.pending as ActivePendingRound;
      expect(p.game.id, 'clubs');
      expect((p.input! as CountsInput).counts, {
        ps[0].id: 3,
        ps[1].id: 2,
        ps[2].id: 0,
        ps[3].id: 0,
      });
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets('back without input on new round shows no dialog and pops', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(calculatorProvider.notifier);
    notifier.startNewGame(players: _makePlayers(), dealerIndex: 0);
    notifier.selectGame(const Clubs());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pumpWidget(_wrapWithNavigator(container));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Terug'));
    await tester.pumpAndSettle();

    expect(find.text('Scores ingevoerd'), findsNothing);
    expect(find.byType(RoundInputScreen), findsNothing);
  });

  testWidgets(
    'back without changes while editing an existing round shows no dialog and pops',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.startNewGame(players: _makePlayers(), dealerIndex: 0);
      final ps = container.read(calculatorProvider).players;
      notifier.selectGame(const Clubs());
      notifier.updateInput(
        CountsInput({ps[0].id: 4, ps[1].id: 4, ps[2].id: 2, ps[3].id: 3}),
      );
      notifier.deselectGame();
      final round = container.read(calculatorProvider).history.first;
      notifier.restoreRound(round);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(_wrapWithNavigator(container));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Terug'));
      await tester.pumpAndSettle();

      expect(find.text('Scores aangepast'), findsNothing);
      expect(find.byType(RoundInputScreen), findsNothing);
    },
  );

  testWidgets(
    'back without changes leaves the active game and pops without a dialog',
    (tester) async {
      // Wrap the screen so we have a route to pop back to.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.startNewGame(players: _makePlayers(), dealerIndex: 0);
      notifier.selectGame(const Clubs());
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RoundInputScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(RoundInputScreen), findsOneWidget);

      // Tap the AppBar's leading back button (tooltip "Terug").
      await tester.tap(find.byTooltip('Terug'));
      await tester.pumpAndSettle();

      // No discard dialog (nothing changed), screen popped,
      // game deselected.
      expect(find.text(kRoundIncompleteTitle), findsNothing);
      expect(find.byType(RoundInputScreen), findsNothing);
      expect(container.read(calculatorProvider).selectedGame, isNull);
    },
  );
}
