import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/widgets/game_input/counts_input.dart';
import 'package:bonken/widgets/game_input/game_input_form.dart';
import 'package:bonken/widgets/game_input/player_picker.dart';

import '_helpers.dart';

void main() {
  group('CountsInput', () {
    testWidgets('renders one row per player and a total label', (tester) async {
      await pumpHost(
        tester,
        CountsInput(
          playerNames: playerNames,
          counts: const [0, 0, 0, 0],
          total: 13,
          unitLabel: 'slagen',
          onCountsChanged: (_) {},
        ),
      );
      for (final n in playerNames) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.textContaining('Totaal: 0 / 13'), findsOneWidget);
    });

    testWidgets('increment button calls onCountsChanged with +1', (
      tester,
    ) async {
      List<int>? captured;
      await pumpHost(
        tester,
        CountsInput(
          playerNames: playerNames,
          counts: const [0, 0, 0, 0],
          total: 13,
          unitLabel: 'slagen',
          onCountsChanged: (c) => captured = c,
        ),
      );
      await tester.tap(find.byIcon(Symbols.add_circle).first);
      await tester.pump();
      expect(captured, [1, 0, 0, 0]);
    });

    testWidgets('decrement button is disabled when count is 0', (tester) async {
      await pumpHost(
        tester,
        CountsInput(
          playerNames: playerNames,
          counts: const [0, 0, 0, 0],
          total: 13,
          unitLabel: 'slagen',
          onCountsChanged: (_) {},
        ),
      );
      final firstMinus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Symbols.remove_circle).first,
      );
      expect(firstMinus.onPressed, isNull);
    });

    testWidgets('increment buttons are disabled when total is reached', (
      tester,
    ) async {
      await pumpHost(
        tester,
        CountsInput(
          playerNames: playerNames,
          counts: const [4, 4, 3, 2], // sum 13
          total: 13,
          unitLabel: 'slagen',
          onCountsChanged: (_) {},
        ),
      );
      final plusButtons = find.widgetWithIcon(IconButton, Symbols.add_circle);
      for (int i = 0; i < plusButtons.evaluate().length; i++) {
        final btn = tester.widget<IconButton>(plusButtons.at(i));
        expect(btn.onPressed, isNull);
      }
    });

    testWidgets(
      '"Alle resterende" button assigns all remaining to that player',
      (tester) async {
        List<int>? captured;
        await pumpHost(
          tester,
          CountsInput(
            playerNames: playerNames,
            counts: const [2, 1, 0, 0],
            total: 13,
            unitLabel: 'slagen',
            onCountsChanged: (c) => captured = c,
          ),
        );
        // Tap Carol's (index 2) "Alle resterende" button.
        final btns = find.widgetWithIcon(
          IconButton,
          Symbols.expand_circle_right,
        );
        await tester.tap(btns.at(2));
        await tester.pump();
        expect(captured, [2, 1, 10, 0]);
      },
    );

    testWidgets('"Alle resterende" button is disabled when total reached', (
      tester,
    ) async {
      await pumpHost(
        tester,
        CountsInput(
          playerNames: playerNames,
          counts: const [4, 4, 3, 2],
          total: 13,
          unitLabel: 'slagen',
          onCountsChanged: (_) {},
        ),
      );
      final btns = find.widgetWithIcon(IconButton, Symbols.expand_circle_right);
      for (int i = 0; i < btns.evaluate().length; i++) {
        final btn = tester.widget<IconButton>(btns.at(i));
        expect(btn.onPressed, isNull);
      }
    });

    testWidgets('ghost-text spacer: string is "12", font is Roboto — '
        'changes to either break the stable-width guarantee', (tester) async {
      // WHY "12" IN ROBOTO:
      // Each _PlayerCountRow renders an invisible Text("12") behind the live
      // count so the stepper column stays a stable width as the count changes
      // (e.g. 9→10). The ghost string must be the WIDEST reachable count in
      // the body font.
      //
      // Per-player counts range 0–13. In Roboto digit glyph widths are NOT
      // proportional to numeric value:
      //   '2' > '0' = '3' >> '1'   (pixels; '1' is much narrower)
      // 2-digit combinations therefore rank:
      //   "12" (1+2) > "10" = "13" (1+0 = 1+3) > "11" (1+1)
      // → "12" is the widest string in the reachable 0–13 set, which lets
      //   the column be as tight as possible without ever causing overflow
      //   or causing adjacent stepper buttons to shift position.
      //
      // If the ghost string ever changes, verify the new value is still the
      // widest reachable count. If the font changes, re-measure digit widths.
      //
      // ExcludeSemantics makes the a11y intent explicit and protects against
      // a hypothetical future alwaysIncludeSemantics: true on the Opacity.
      await pumpHost(
        tester,
        CountsInput(
          playerNames: playerNames,
          counts: const [0, 0, 0, 0],
          total: 13,
          unitLabel: 'slagen',
          onCountsChanged: (_) {},
        ),
      );

      // Exactly one invisible ghost Text per player row, wrapped in
      // ExcludeSemantics (outer) so the layout spacer is never announced by
      // screen readers.
      final ghostFinder = find.byWidgetPredicate(
        (w) =>
            w is ExcludeSemantics &&
            w.child is Opacity &&
            (w.child as Opacity).opacity == 0.0 &&
            (w.child as Opacity).child is Text &&
            ((w.child as Opacity).child as Text).data == '12',
      );
      expect(ghostFinder, findsNWidgets(playerNames.length));

      final excludeSem = tester.widget<ExcludeSemantics>(ghostFinder.first);
      final ghostOpacity = excludeSem.child! as Opacity;
      final ghostText = ghostOpacity.child! as Text;
      expect(ghostText.data, '12');
      // Font must stay Roboto; the "12 is widest" claim is metric-specific.
      expect(ghostText.style?.fontFamily, 'Roboto');
    });
  });

  group('PlayerPicker', () {
    testWidgets('shows the prompt and all four player names', (tester) async {
      await pumpHost(
        tester,
        PlayerPicker(
          playerNames: playerNames,
          selectedIndex: null,
          prompt: 'Wie wint?',
          onSelected: (_) {},
        ),
      );
      expect(find.text('Wie wint?'), findsOneWidget);
      for (final n in playerNames) {
        expect(find.text(n), findsOneWidget);
      }
    });

    testWidgets('tapping a player calls onSelected with that index', (
      tester,
    ) async {
      int? selected;
      await pumpHost(
        tester,
        PlayerPicker(
          playerNames: playerNames,
          selectedIndex: null,
          prompt: 'Wie?',
          onSelected: (i) => selected = i,
        ),
      );
      await tester.tap(find.text('Carol'));
      await tester.pump();
      expect(selected, 2);
    });

    testWidgets('tapping the selected player again deselects it (emits null)', (
      tester,
    ) async {
      int? selected = 2; // Carol pre-selected.
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (context, setState) => PlayerPicker(
            playerNames: playerNames,
            selectedIndex: selected,
            prompt: 'Wie?',
            onSelected: (i) => setState(() => selected = i),
          ),
        ),
      );
      await tester.tap(find.text('Carol'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    });

    testWidgets(
      'with no selection, no tile is dimmed (Opacity wrapper absent)',
      (tester) async {
        await pumpHost(
          tester,
          PlayerPicker(
            playerNames: playerNames,
            selectedIndex: null,
            prompt: 'Wie?',
            onSelected: (_) {},
          ),
        );
        // Only the descendants of the picker matter — Material/InkWell
        // can introduce their own animation Opacity layers we don't
        // care about.
        expect(
          find.descendant(
            of: find.byType(PlayerPicker),
            matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity == 0.38,
            ),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'with a selection, the other three tiles render at 0.38 opacity '
      'and remain tappable',
      (tester) async {
        int? selected;
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (context, setState) => PlayerPicker(
              playerNames: playerNames,
              selectedIndex: selected,
              prompt: 'Wie?',
              onSelected: (i) => setState(() => selected = i),
            ),
          ),
        );
        await tester.tap(find.text('Bob'));
        await tester.pumpAndSettle();
        expect(selected, 1);

        // Three of the four tiles get an Opacity(0.38) ancestor.
        expect(
          find.descendant(
            of: find.byType(PlayerPicker),
            matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity == 0.38,
            ),
          ),
          findsNWidgets(3),
        );

        // A dimmed tile is still tappable: tapping Carol switches the
        // selection from Bob to Carol.
        await tester.tap(find.text('Carol'));
        await tester.pumpAndSettle();
        expect(selected, 2);
      },
    );
  });

  group('GameInputForm with DualPlayerInputDescriptor', () {
    testWidgets('shows two prompts', (tester) async {
      await pumpHost(
        tester,
        GameInputForm(
          game: const SeventhAndThirteenth(),
          players: players,
          input: const {'player1': null, 'player2': null},
          onInputChanged: (_, _) {},
        ),
      );
      expect(find.text('Wie won de 7e slag?'), findsOneWidget);
      expect(find.text('Wie won de 13e slag?'), findsOneWidget);
    });

    testWidgets('callbacks fire independently per picker', (tester) async {
      final updates = <(String, dynamic)>[];
      await pumpHost(
        tester,
        GameInputForm(
          game: const SeventhAndThirteenth(),
          players: players,
          input: const {'player1': null, 'player2': null},
          onInputChanged: (key, value) => updates.add((key, value)),
        ),
      );
      // Each player name appears twice (once per picker).
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      await tester.tap(find.text('Dan').last);
      await tester.pump();
      expect(updates, [('player1', players[0].id), ('player2', players[3].id)]);
    });
  });

  group('GameInputForm with SinglePlayerInputDescriptor', () {
    testWidgets('tapping the selected player again writes null (deselect)', (
      tester,
    ) async {
      final updates = <(String, dynamic)>[];
      await pumpHost(
        tester,
        GameInputForm(
          game: const KingOfHearts(),
          players: players,
          input: {'player': players[2].id}, // Carol pre-selected.
          onInputChanged: (key, value) => updates.add((key, value)),
        ),
      );
      await tester.tap(find.text('Carol'));
      await tester.pump();
      expect(updates, [('player', null)]);
    });
  });
}
