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
      final plusButtons = find.widgetWithIcon(
        IconButton,
        Symbols.add_circle,
      );
      for (int i = 0; i < plusButtons.evaluate().length; i++) {
        final btn = tester.widget<IconButton>(plusButtons.at(i));
        expect(btn.onPressed, isNull);
      }
    });

    testWidgets('"Alle resterende" button assigns all remaining to that player',
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
    });

    testWidgets('"Alle resterende" button is disabled when total reached',
        (tester) async {
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
      final btns = find.widgetWithIcon(
        IconButton,
        Symbols.expand_circle_right,
      );
      for (int i = 0; i < btns.evaluate().length; i++) {
        final btn = tester.widget<IconButton>(btns.at(i));
        expect(btn.onPressed, isNull);
      }
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
  });

  group('GameInputForm with DualPlayerInputDescriptor', () {
    testWidgets('shows two prompts', (tester) async {
      await pumpHost(
        tester,
        GameInputForm(
          game: const SeventhAndThirteenth(),
          playerNames: playerNames,
          input: const {'trick7winner': null, 'trick13winner': null},
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
          playerNames: playerNames,
          input: const {'trick7winner': null, 'trick13winner': null},
          onInputChanged: (key, value) => updates.add((key, value)),
        ),
      );
      // Each player name appears twice (once per picker).
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      await tester.tap(find.text('Dan').last);
      await tester.pump();
      expect(updates, [
        ('trick7winner', 0),
        ('trick13winner', 3),
      ]);
    });
  });
}
