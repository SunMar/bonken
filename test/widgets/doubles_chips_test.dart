import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/widgets/doubles_chips.dart';

import '_helpers.dart';

/// Returns the visible chip labels in their on-screen left-to-right,
/// top-to-bottom order.
List<String> chipLabels(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(DoublesChips),
    matching: find.byType(Text),
  );
  return tester
      .widgetList<Text>(texts)
      .map((t) => t.data ?? '')
      .toList(growable: false);
}

void main() {
  group('DoublesChips ordering', () {
    testWidgets(
      'orders by initiator turn position '
      '(chooser+1 first, chooser last)',
      (tester) async {
        // Chooser = 1 (Bob). Doubling order: Carol(2) -> Dan(3) -> Alice(0) -> Bob(1).
        // Build doubles in deliberately mixed pair order:
        //   - Bob (chooser, turn 3) doubled by Alice via redouble?  No — chooser
        //     can only redouble. So set Bob redoubles Carol.
        //   - Alice (turn 2) doubles Dan
        //   - Carol (turn 0) doubles Alice
        // Pairs are stored unordered; we set initiator explicitly per pair.
        final doubles = DoubleMatrix.empty()
            // Carol (turn 0) doubles Alice
            .withPair(0, 2, DoubleState.doubled, initiator: 2)
            // Alice (turn 2) doubles Dan
            .withPair(0, 3, DoubleState.doubled, initiator: 0)
            // Bob (chooser, turn 3) redoubles Carol who doubled Bob
            .withPair(1, 2, DoubleState.redoubled, initiator: 1);

        await pumpHost(
          tester,
          DoublesChips(
            doubles: doubles,
            names: playerNames,
            chooserIndex: 1,
          ),
        );

        expect(chipLabels(tester), [
          'Carol × Alice', // initiator turn 0
          'Alice × Dan', // initiator turn 2
          'Bob ×× Carol', // initiator turn 3 (chooser)
        ]);
      },
    );

    testWidgets(
      'breaks ties on initiator by other player turn position',
      (tester) async {
        // Chooser = 0 (Alice). Doubling order: Bob(1) -> Carol(2) -> Dan(3) -> Alice(0).
        // Bob (turn 0) doubles all three other players.  Expected target order:
        // Carol (turn 1), Dan (turn 2), Alice (turn 3).
        final doubles = DoubleMatrix.empty()
            // Insert in mixed order to prove sorting drives the result.
            .withPair(0, 1, DoubleState.doubled, initiator: 1) // Bob -> Alice
            .withPair(1, 3, DoubleState.doubled, initiator: 1) // Bob -> Dan
            .withPair(1, 2, DoubleState.doubled, initiator: 1); // Bob -> Carol

        await pumpHost(
          tester,
          DoublesChips(
            doubles: doubles,
            names: playerNames,
            chooserIndex: 0,
          ),
        );

        expect(chipLabels(tester), [
          'Bob × Carol',
          'Bob × Dan',
          'Bob × Alice',
        ]);
      },
    );

    testWidgets('renders nothing when there are no active doubles', (
      tester,
    ) async {
      await pumpHost(
        tester,
        DoublesChips(
          doubles: DoubleMatrix.empty(),
          names: playerNames,
          chooserIndex: 0,
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });
}
