import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/widgets/game_input/counts_input.dart';
import 'package:bonken/widgets/game_input/player_picker.dart';
import 'package:bonken/widgets/game_input/dual_player_picker.dart';

const playerNames = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<void> pumpHost(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

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
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
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
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline).first,
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
        Icons.add_circle_outline,
      );
      for (int i = 0; i < plusButtons.evaluate().length; i++) {
        final btn = tester.widget<IconButton>(plusButtons.at(i));
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

  group('DualPlayerPicker', () {
    testWidgets('shows two prompts', (tester) async {
      await pumpHost(
        tester,
        DualPlayerPicker(
          playerNames: playerNames,
          selectedIndex1: null,
          prompt1: 'Wie won 7e?',
          onSelected1: (_) {},
          selectedIndex2: null,
          prompt2: 'Wie won 13e?',
          onSelected2: (_) {},
        ),
      );
      expect(find.text('Wie won 7e?'), findsOneWidget);
      expect(find.text('Wie won 13e?'), findsOneWidget);
    });

    testWidgets('callbacks fire independently per picker', (tester) async {
      int? sel1;
      int? sel2;
      await pumpHost(
        tester,
        DualPlayerPicker(
          playerNames: playerNames,
          selectedIndex1: null,
          prompt1: 'P1',
          onSelected1: (i) => sel1 = i,
          selectedIndex2: null,
          prompt2: 'P2',
          onSelected2: (i) => sel2 = i,
        ),
      );
      // Each player name appears twice (once per picker).
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      await tester.tap(find.text('Dan').last);
      await tester.pump();
      expect(sel1, 0);
      expect(sel2, 3);
    });
  });
}
