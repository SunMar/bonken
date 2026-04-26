import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/widgets/doubles_picker.dart';

const playerNames = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<void> pumpHost(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('DoublesPicker', () {
    testWidgets('shows the doubling order with chooser last', (tester) async {
      await pumpHost(
        tester,
        DoublesPicker(
          playerNames: playerNames,
          chooserIndex: 1, // Bob chose → order: Carol → Dan → Alice → Bob
          doubles: DoubleMatrix.empty(),
          onChanged: (_) {},
        ),
      );
      expect(find.text('Volgorde: Carol → Dan → Alice → Bob'), findsOneWidget);
    });

    testWidgets('renders all 4 initiator names twice (initiator+target lists)', (
      tester,
    ) async {
      await pumpHost(
        tester,
        DoublesPicker(
          playerNames: playerNames,
          chooserIndex: 0,
          doubles: DoubleMatrix.empty(),
          onChanged: (_) {},
        ),
      );
      // Each player appears once in initiator list and once in target list = 2x.
      for (final n in playerNames) {
        expect(find.text(n), findsNWidgets(2));
      }
    });

    testWidgets('tapping initiator + target cycles to "doubled"', (
      tester,
    ) async {
      DoubleMatrix? captured;
      await pumpHost(
        tester,
        DoublesPicker(
          playerNames: playerNames,
          chooserIndex: 3, // Dan chose → first to double = Alice
          doubles: DoubleMatrix.empty(),
          onChanged: (m) => captured = m,
        ),
      );
      // Tap Alice in the initiator list (first occurrence).
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      // Now tap Bob in the target list (second occurrence).
      await tester.tap(find.text('Bob').last);
      await tester.pump();
      expect(captured, isNotNull);
      expect(captured!.stateFor(0, 1), DoubleState.doubled);
      expect(captured!.initiatorFor(0, 1), 0);
    });
  });
}
