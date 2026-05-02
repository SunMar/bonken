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

    testWidgets(
      '"Slappe hap" — re-press when all targets activated clears them',
      (tester) async {
        // chooser=0, Bob(1) initiator. After Slappe hap, (1,2) and (1,3) are
        // doubled. Pressing it again should reset both to none.
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
        // Now button should be a FilledButton (applied state).
        expect(
          find.widgetWithText(FilledButton, 'Slappe hap'),
          findsOneWidget,
        );
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(1, 2), DoubleState.none);
        expect(matrix.stateFor(1, 3), DoubleState.none);
        // And the button is back to outlined.
        expect(
          find.widgetWithText(OutlinedButton, 'Slappe hap'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '"Slappe hap" stays filled after a target redoubles; re-press clears all incl. redoubles',
      (tester) async {
        // chooser=0 (Alice). Bob(1) initiator. Bob doubled both non-choosers
        // (Carol & Dan); Carol then redoubled Bob. State: (1,2)=redoubled
        // initiator=Bob, (1,3)=doubled initiator=Bob. Slappe hap stays
        // filled, and re-press clears both pairs to none (input correction).
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 2, DoubleState.redoubled, initiator: 1)
            .withPair(1, 3, DoubleState.doubled, initiator: 1);
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
        expect(
          find.widgetWithText(FilledButton, 'Slappe hap'),
          findsOneWidget,
        );
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(1, 2), DoubleState.none);
        expect(matrix.stateFor(1, 3), DoubleState.none);
      },
    );

    testWidgets(
      '"Slappe hap" from a partial state (chooser + 1 other doubled) transitions to Slappe hap',
      (tester) async {
        // chooser=2 (Carol), Bob(1) initiator. Bob has already doubled
        // chooser (1,2) and Alice (1,0). Pressing Slappe hap should
        // deselect the chooser pair and ensure Dan (1,3) is also doubled.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 2, DoubleState.doubled, initiator: 1)
            .withPair(1, 0, DoubleState.doubled, initiator: 1);
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 2,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(1, 2), DoubleState.none);
        expect(matrix.stateFor(1, 0), DoubleState.doubled);
        expect(matrix.stateFor(1, 3), DoubleState.doubled);
        expect(
          find.widgetWithText(FilledButton, 'Slappe hap'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Zaal'), findsOneWidget);
      },
    );

    testWidgets(
      '"Slappe hap" transition demotes a redoubled chooser pair instead of clearing it',
      (tester) async {
        // chooser=2, Bob(1) initiator. (1,2) is redoubled (Carol redoubled
        // Bob's double). Pressing Slappe hap should demote (1,2) to doubled
        // (initiator=Carol) and double the others.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 2, DoubleState.redoubled, initiator: 2);
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 2,
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
        expect(matrix.initiatorFor(1, 2), 2);
        expect(matrix.stateFor(1, 0), DoubleState.doubled);
        expect(matrix.stateFor(1, 3), DoubleState.doubled);
      },
    );

    testWidgets('"Zaal" — re-press when all targets activated clears them', (
      tester,
    ) async {
      // chooser=2 (Carol). Bob(1) initiator → Zaal targets all 3 others.
      DoubleMatrix matrix = DoubleMatrix.empty();
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (ctx, setState) => DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 2,
            doubles: matrix,
            onChanged: (m) => setState(() => matrix = m),
          ),
        ),
      );
      await tester.tap(find.text('Bob').first);
      await tester.pump();
      await tester.tap(find.text('Zaal'));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Zaal'), findsOneWidget);
      expect(matrix.stateFor(1, 0), DoubleState.doubled);
      expect(matrix.stateFor(1, 2), DoubleState.doubled);
      expect(matrix.stateFor(1, 3), DoubleState.doubled);
      // Re-press clears all.
      await tester.tap(find.text('Zaal'));
      await tester.pump();
      expect(matrix.stateFor(1, 0), DoubleState.none);
      expect(matrix.stateFor(1, 2), DoubleState.none);
      expect(matrix.stateFor(1, 3), DoubleState.none);
    });

    testWidgets(
      'when "Zaal" is applied, "Slappe hap" is outlined; pressing it clears the chooser pair',
      (tester) async {
        // chooser=2 (Carol). Bob(1) initiator. Apply Zaal → all 3 doubled.
        DoubleMatrix matrix = DoubleMatrix.empty();
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 2,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        await tester.tap(find.text('Zaal'));
        await tester.pump();
        // Zaal is filled, Slappe hap stays outlined (not also filled).
        expect(find.widgetWithText(FilledButton, 'Zaal'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Slappe hap'),
          findsOneWidget,
        );
        // Pressing Slappe hap clears just the chooser pair → Slappe hap state.
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(1, 2), DoubleState.none);
        expect(matrix.stateFor(1, 0), DoubleState.doubled);
        expect(matrix.stateFor(1, 3), DoubleState.doubled);
        // Now Slappe hap is filled, Zaal is outlined.
        expect(
          find.widgetWithText(FilledButton, 'Slappe hap'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Zaal'), findsOneWidget);
      },
    );

    testWidgets(
      '"Zaal terug" re-press demotes redoubles back to doubled, preserving initiator',
      (tester) async {
        // chooser=0 (Alice). All 3 others doubled Alice.
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
        // Apply Zaal terug.
        await tester.tap(find.text('Zaal terug'));
        await tester.pump();
        for (final t in [1, 2, 3]) {
          expect(matrix.stateFor(0, t), DoubleState.redoubled);
        }
        // Now button should be filled.
        expect(
          find.widgetWithText(FilledButton, 'Zaal terug'),
          findsOneWidget,
        );
        // Re-press: redoubles demote to doubled, original initiators kept;
        // doubles are NOT cleared.
        await tester.tap(find.text('Zaal terug'));
        await tester.pump();
        for (final t in [1, 2, 3]) {
          expect(matrix.stateFor(0, t), DoubleState.doubled);
          expect(matrix.initiatorFor(0, t), t);
        }
      },
    );
    testWidgets(
      '"Slappe hap" stays outlined when a target doubled the initiator but no redouble back',
      (tester) async {
        // chooser=0. Bob(1) initiator. Carol(2) doubled Bob — pair is
        // doubled, initiator=Carol. Bob hasn't acted on Carol yet, so
        // Slappe hap should be outlined (not filled).
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 2, DoubleState.doubled, initiator: 2);
        await pumpHost(
          tester,
          DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 0,
            doubles: matrix,
            onChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        expect(
          find.widgetWithText(OutlinedButton, 'Slappe hap'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '"Slappe hap" is filled when initiator redoubled a target that had doubled them',
      (tester) async {
        // chooser=0. Bob(1) initiator. Carol(2) doubled Bob → Bob redoubled
        // Carol (state=redoubled, initiator=Carol). Bob doubled Dan(3).
        // Slappe hap targets {2,3} both show initiator-action → filled.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 2, DoubleState.redoubled, initiator: 2)
            .withPair(1, 3, DoubleState.doubled, initiator: 1);
        await pumpHost(
          tester,
          DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 0,
            doubles: matrix,
            onChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        expect(
          find.widgetWithText(FilledButton, 'Slappe hap'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '"Zaal" stays filled when targets redouble back; re-press clears all incl. redoubles',
      (tester) async {
        // chooser=2 (Carol). Bob(1) initiator doubled all 3 (Zaal). Alice
        // and Dan redoubled Bob back. Button should still be filled because
        // the initiator acted on every pair. Re-press clears everything to
        // none (input correction).
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 0, DoubleState.redoubled, initiator: 1)
            .withPair(1, 2, DoubleState.doubled, initiator: 1)
            .withPair(1, 3, DoubleState.redoubled, initiator: 1);
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 2,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        expect(find.widgetWithText(FilledButton, 'Zaal'), findsOneWidget);
        await tester.tap(find.text('Zaal'));
        await tester.pump();
        for (final t in [0, 2, 3]) {
          expect(matrix.stateFor(1, t), DoubleState.none);
        }
      },
    );

    testWidgets(
      '"Terug op beide" — chooser doubled by exactly 2 → bulk redouble those two',
      (tester) async {
        // chooser=2 (Carol). Alice and Dan doubled Carol; Bob did not.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(2, 0, DoubleState.doubled, initiator: 0)
            .withPair(2, 3, DoubleState.doubled, initiator: 3);
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 2,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Carol').first);
        await tester.pump();
        // Label is "Terug op beide", not "Zaal terug" or "Zaal".
        expect(find.text('Terug op beide'), findsOneWidget);
        expect(find.text('Zaal terug'), findsNothing);
        // Outlined initially (neither redoubled).
        expect(
          find.widgetWithText(OutlinedButton, 'Terug op beide'),
          findsOneWidget,
        );
        await tester.tap(find.text('Terug op beide'));
        await tester.pump();
        expect(matrix.stateFor(2, 0), DoubleState.redoubled);
        expect(matrix.initiatorFor(2, 0), 0);
        expect(matrix.stateFor(2, 3), DoubleState.redoubled);
        expect(matrix.initiatorFor(2, 3), 3);
        // Bob's pair untouched.
        expect(matrix.stateFor(2, 1), DoubleState.none);
        // Now filled.
        expect(
          find.widgetWithText(FilledButton, 'Terug op beide'),
          findsOneWidget,
        );
        // Re-press demotes back to doubled with original initiators.
        await tester.tap(find.text('Terug op beide'));
        await tester.pump();
        expect(matrix.stateFor(2, 0), DoubleState.doubled);
        expect(matrix.initiatorFor(2, 0), 0);
        expect(matrix.stateFor(2, 3), DoubleState.doubled);
        expect(matrix.initiatorFor(2, 3), 3);
      },
    );

    testWidgets(
      '"Terug op beide" outlined when only one of the two doublers has been redoubled',
      (tester) async {
        // chooser=2. Alice doubled; Dan doubled then Carol redoubled Dan.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(2, 0, DoubleState.doubled, initiator: 0)
            .withPair(2, 3, DoubleState.redoubled, initiator: 3);
        await pumpHost(
          tester,
          DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 2,
            doubles: matrix,
            onChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Carol').first);
        await tester.pump();
        expect(
          find.widgetWithText(OutlinedButton, 'Terug op beide'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'chooser doubled by only one player → Zaal button stays disabled',
      (tester) async {
        // chooser=2. Only Alice doubled Carol.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(2, 0, DoubleState.doubled, initiator: 0);
        await pumpHost(
          tester,
          DoublesPicker(
            playerNames: playerNames,
            chooserIndex: 2,
            doubles: matrix,
            onChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Carol').first);
        await tester.pump();
        // Label remains "Zaal" (not enough doublers for the terug variant).
        expect(find.text('Zaal'), findsOneWidget);
        expect(find.text('Terug op beide'), findsNothing);
        expect(find.text('Zaal terug'), findsNothing);
        final btn = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Zaal'),
        );
        expect(btn.onPressed, isNull);
      },
    );

    testWidgets(
      '"Slappe hap" after Zaal+chooser-redouble clears the chooser pair entirely',
      (tester) async {
        // chooser=2 (Carol). Bob(1) initiator did Zaal: doubled all 3
        // including Carol → (1,2)=doubled initiator=Bob. Carol then
        // redoubled Bob → (1,2)=redoubled initiator=Bob. Pressing Slappe
        // hap should clear (1,2) entirely (Bob initiated the whole pair),
        // not just demote to doubled.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(1, 0, DoubleState.doubled, initiator: 1)
            .withPair(1, 2, DoubleState.redoubled, initiator: 1)
            .withPair(1, 3, DoubleState.doubled, initiator: 1);
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              playerNames: playerNames,
              chooserIndex: 2,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(1, 2), DoubleState.none);
        expect(matrix.stateFor(1, 0), DoubleState.doubled);
        expect(matrix.stateFor(1, 3), DoubleState.doubled);
      },
    );

  });
}
