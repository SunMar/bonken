import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/widgets/doubles_picker.dart';

import '_helpers.dart';

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

    testWidgets(
      'turn order: target later than initiator → full cycle through redoubled',
      (tester) async {
        // chooserIndex=2 → doubling order: Dan(3) → Alice(0) → Bob(1) → Carol(2).
        // Dan(3) is at turnIndex 0; Carol(2) is at turnIndex 3.
        // Since target's turn comes AFTER initiator's, the cycle is
        // none → doubled → redoubled → none.
        DoubleMatrix matrix = DoubleMatrix.empty();
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) {
              return DoublesPicker(
                playerNames: playerNames,
                chooserIndex: 2,
                doubles: matrix,
                onChanged: (m) => setState(() => matrix = m),
              );
            },
          ),
        );
        await tester.tap(find.text('Dan').first);
        await tester.pump();
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(matrix.stateFor(2, 3), DoubleState.doubled);
        expect(matrix.initiatorFor(2, 3), 3);
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(matrix.stateFor(2, 3), DoubleState.redoubled);
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(matrix.stateFor(2, 3), DoubleState.none);
      },
    );

    testWidgets('"Zaal terug" — chooser doubled by all 3 → bulk redouble', (
      tester,
    ) async {
      // chooser=0 (Alice). All 3 others doubled Alice with themselves as initiator.
      DoubleMatrix matrix = DoubleMatrix.empty()
          .withPair(0, 1, DoubleState.doubled, initiator: 1)
          .withPair(0, 2, DoubleState.doubled, initiator: 2)
          .withPair(0, 3, DoubleState.doubled, initiator: 3);
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (ctx, setState) => DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 0,
            doubles: matrix,
            onChanged: (m) => setState(() => matrix = m),
          ),
        ),
      );
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      // Button should now read "Zaal terug".
      expect(find.text('Zaal terug'), findsOneWidget);
      await tester.tap(find.text('Zaal terug'));
      await tester.pump();
      // All three pairs become redoubled with original initiators preserved.
      for (final t in [1, 2, 3]) {
        expect(matrix.stateFor(0, t), DoubleState.redoubled);
        expect(matrix.initiatorFor(0, t), t);
      }
    });

    testWidgets(
      '"Zaal terug" — mixed: already-redoubled pair stays untouched',
      (tester) async {
        // chooser=0 (Alice). (0,1) already redoubled by 1; (0,2) and (0,3) only
        // doubled by 2 and 3.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(0, 1, DoubleState.redoubled, initiator: 1)
            .withPair(0, 2, DoubleState.doubled, initiator: 2)
            .withPair(0, 3, DoubleState.doubled, initiator: 3);
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 0,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Alice').first);
        await tester.pump();
        expect(find.text('Zaal terug'), findsOneWidget);
        await tester.tap(find.text('Zaal terug'));
        await tester.pump();
        // (0,1) was redoubled → unchanged; (0,2)/(0,3) escalate to redoubled.
        expect(matrix.stateFor(0, 1), DoubleState.redoubled);
        expect(matrix.initiatorFor(0, 1), 1);
        expect(matrix.stateFor(0, 2), DoubleState.redoubled);
        expect(matrix.initiatorFor(0, 2), 2);
        expect(matrix.stateFor(0, 3), DoubleState.redoubled);
        expect(matrix.initiatorFor(0, 3), 3);
      },
    );

    testWidgets('"Slappe hap" — selected initiator doubles all non-choosers', (
      tester,
    ) async {
      // chooser=0, initiator Bob(1). "Slappe hap" → Bob doubles Carol(2) and
      // Dan(3) but NOT Alice(0, the chooser).
      DoubleMatrix matrix = DoubleMatrix.empty();
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (ctx, setState) => DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 0,
            doubles: matrix,
            onChanged: (m) => setState(() => matrix = m),
          ),
        ),
      );
      await tester.tap(find.text('Bob').first);
      await tester.pump();
      await tester.tap(find.text('Slappe hap'));
      await tester.pump();
      expect(matrix.stateFor(1, 2), DoubleState.doubled);
      expect(matrix.initiatorFor(1, 2), 1);
      expect(matrix.stateFor(1, 3), DoubleState.doubled);
      expect(matrix.initiatorFor(1, 3), 1);
      // (0,1) — chooser pair — must remain none.
      expect(matrix.stateFor(0, 1), DoubleState.none);
    });

    testWidgets(
      'chooser cannot initiate doubles: tap is no-op, "Slappe hap" disabled',
      (tester) async {
        DoubleMatrix? captured;
        await pumpHost(
          tester,
          DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 0,
            doubles: DoubleMatrix.empty(),
            onChanged: (m) => captured = m,
          ),
        );
        // Select chooser as initiator.
        await tester.tap(find.text('Alice').first);
        await tester.pump();
        // Tap a target (Bob) that has no double yet → must not fire onChanged.
        await tester.tap(find.text('Bob').last);
        await tester.pump();
        expect(captured, isNull);
        // "Slappe hap" button is disabled.
        final slappe = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Slappe hap'),
        );
        expect(slappe.onPressed, isNull);
      },
    );
  });
}
