import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/widgets/doubles_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('DoublesPicker', () {
    testWidgets('shows the doubling order with chooser last', (tester) async {
      await pumpHost(
        tester,
        DoublesPicker(
          players: players,
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
          players: players,
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
          players: players,
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
      expect(
        captured!.stateFor(playerIds[0], playerIds[1]),
        DoubleState.doubled,
      );
      expect(captured!.initiatorFor(playerIds[0], playerIds[1]), playerIds[0]);
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
                players: players,
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
        expect(
          matrix.stateFor(playerIds[2], playerIds[3]),
          DoubleState.doubled,
        );
        expect(matrix.initiatorFor(playerIds[2], playerIds[3]), playerIds[3]);
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(
          matrix.stateFor(playerIds[2], playerIds[3]),
          DoubleState.redoubled,
        );
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(matrix.stateFor(playerIds[2], playerIds[3]), DoubleState.none);
      },
    );

    testWidgets('"Zaal terug" — chooser doubled by all 3 → bulk redouble', (
      tester,
    ) async {
      // chooser=0 (Alice). All 3 others doubled Alice with themselves as initiator.
      DoubleMatrix matrix = DoubleMatrix.empty()
          .withPair(
            playerIds[0],
            playerIds[1],
            DoubleState.doubled,
            initiator: playerIds[1],
          )
          .withPair(
            playerIds[0],
            playerIds[2],
            DoubleState.doubled,
            initiator: playerIds[2],
          )
          .withPair(
            playerIds[0],
            playerIds[3],
            DoubleState.doubled,
            initiator: playerIds[3],
          );
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (ctx, setState) => DoublesPicker(
            players: players,
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
        expect(
          matrix.stateFor(playerIds[0], playerIds[t]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[t]), playerIds[t]);
      }
    });

    testWidgets(
      '"Zaal terug" — mixed: already-redoubled pair stays untouched',
      (tester) async {
        // chooser=0 (Alice). (0,1) already redoubled by 1; (0,2) and (0,3) only
        // doubled by 2 and 3.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(
              playerIds[0],
              playerIds[1],
              DoubleState.redoubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[0],
              playerIds[2],
              DoubleState.doubled,
              initiator: playerIds[2],
            )
            .withPair(
              playerIds[0],
              playerIds[3],
              DoubleState.doubled,
              initiator: playerIds[3],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
        expect(
          matrix.stateFor(playerIds[0], playerIds[1]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[1]), playerIds[1]);
        expect(
          matrix.stateFor(playerIds[0], playerIds[2]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[2]), playerIds[2]);
        expect(
          matrix.stateFor(playerIds[0], playerIds[3]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[3]), playerIds[3]);
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
            players: players,
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
      expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.doubled);
      expect(matrix.initiatorFor(playerIds[1], playerIds[2]), playerIds[1]);
      expect(matrix.stateFor(playerIds[1], playerIds[3]), DoubleState.doubled);
      expect(matrix.initiatorFor(playerIds[1], playerIds[3]), playerIds[1]);
      // (0,1) — chooser pair — must remain none.
      expect(matrix.stateFor(playerIds[0], playerIds[1]), DoubleState.none);
    });

    testWidgets('chooser initiating shows the override dialog; cancel = no-op, '
        '"Slappe hap" disabled', (tester) async {
      DoubleMatrix? captured;
      await pumpHost(
        tester,
        DoublesPicker(
          players: players,
          chooserIndex: 0,
          doubles: DoubleMatrix.empty(),
          onChanged: (m) => captured = m,
        ),
      );
      // Select chooser as initiator.
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      // Tap a target (Bob) with no double yet → disabled-looking but
      // tappable: opens the override dialog instead of doubling silently.
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
      expect(find.text('Kiezer mag niet dubbelen'), findsOneWidget);
      // Cancelling leaves the matrix untouched.
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(captured, isNull);
      // "Slappe hap" button is still disabled for the chooser.
      final slappe = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Slappe hap'),
      );
      expect(slappe.onPressed, isNull);
    });

    testWidgets(
      'chooser initiating can be forced via "Toch dubbelen"; re-tap clears it',
      (tester) async {
        DoubleMatrix matrix = DoubleMatrix.empty();
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
              chooserIndex: 0, // Alice is the chooser.
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Alice').first);
        await tester.pump();
        await tester.tap(find.text('Bob').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Toch dubbelen'));
        await tester.pumpAndSettle();
        expect(
          matrix.stateFor(playerIds[0], playerIds[1]),
          DoubleState.doubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[1]), playerIds[0]);
        // Re-tapping the forced tile clears it — an undo needs no prompt.
        await tester.tap(find.text('Bob').last);
        await tester.pumpAndSettle();
        expect(find.text('Kiezer mag niet dubbelen'), findsNothing);
        expect(matrix.stateFor(playerIds[0], playerIds[1]), DoubleState.none);
      },
    );

    testWidgets(
      'redouble after your turn passed: forced via "Toch teruggaan"',
      (tester) async {
        // chooserIndex 3 → order Alice→Bob→Carol→Dan. Alice (turn 0) was
        // doubled by Bob (turn 1), so Alice's turn to go back has passed.
        DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[0],
          playerIds[1],
          DoubleState.doubled,
          initiator: playerIds[1],
        );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
              chooserIndex: 3,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Alice').first);
        await tester.pump();
        await tester.tap(find.text('Bob').last);
        await tester.pumpAndSettle();
        expect(find.text('Beurt voorbij'), findsOneWidget);
        await tester.tap(find.text('Toch teruggaan'));
        await tester.pumpAndSettle();
        expect(
          matrix.stateFor(playerIds[0], playerIds[1]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[1]), playerIds[1]);
      },
    );

    testWidgets('redouble after turn passed: cancel leaves it unchanged', (
      tester,
    ) async {
      DoubleMatrix matrix = DoubleMatrix.empty().withPair(
        playerIds[0],
        playerIds[1],
        DoubleState.doubled,
        initiator: playerIds[1],
      );
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (ctx, setState) => DoublesPicker(
            players: players,
            chooserIndex: 3,
            doubles: matrix,
            onChanged: (m) => setState(() => matrix = m),
          ),
        ),
      );
      await tester.tap(find.text('Alice').first);
      await tester.pump();
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(matrix.stateFor(playerIds[0], playerIds[1]), DoubleState.doubled);
    });

    testWidgets(
      'forced (turn-passed) redouble can be undone without a prompt',
      (tester) async {
        DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[0],
          playerIds[1],
          DoubleState.redoubled,
          initiator: playerIds[1],
        );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
              chooserIndex: 3,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Alice').first);
        await tester.pump();
        await tester.tap(find.text('Bob').last);
        await tester.pumpAndSettle();
        // Undo toggles straight back to doubled, no dialog.
        expect(find.text('Beurt voorbij'), findsNothing);
        expect(
          matrix.stateFor(playerIds[0], playerIds[1]),
          DoubleState.doubled,
        );
      },
    );

    testWidgets(
      'redouble while your turn has NOT passed: toggles directly, no dialog',
      (tester) async {
        // chooserIndex 3 → order Alice→Bob→Carol→Dan. Alice (turn 0) doubled
        // Bob (turn 1); Bob's turn comes later, so Bob may still go back.
        DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[0],
          playerIds[1],
          DoubleState.doubled,
          initiator: playerIds[0],
        );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
              chooserIndex: 3,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Bob').first); // Bob goes back on Alice
        await tester.pump();
        await tester.tap(find.text('Alice').last);
        await tester.pumpAndSettle();
        // Allowed redouble: no force dialog, initiator preserved.
        expect(find.text('Beurt voorbij'), findsNothing);
        expect(
          matrix.stateFor(playerIds[0], playerIds[1]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[0], playerIds[1]), playerIds[0]);
      },
    );

    testWidgets(
      'chooser undo of a forced double clears a redouble-on-top too',
      (tester) async {
        // chooser=0 (Alice) initiated a double on Bob (only possible via the
        // force override); Bob then redoubled. Undoing from the chooser side
        // clears the whole pair.
        DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[0],
          playerIds[1],
          DoubleState.redoubled,
          initiator: playerIds[0],
        );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
              chooserIndex: 0,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Alice').first); // the chooser
        await tester.pump();
        await tester.tap(find.text('Bob').last);
        await tester.pumpAndSettle();
        // Undo, not a new force → no dialog, and the pair is fully cleared.
        expect(find.text('Kiezer mag niet dubbelen'), findsNothing);
        expect(matrix.stateFor(playerIds[0], playerIds[1]), DoubleState.none);
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
              players: players,
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
        expect(find.widgetWithText(FilledButton, 'Slappe hap'), findsOneWidget);
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.none);
        expect(matrix.stateFor(playerIds[1], playerIds[3]), DoubleState.none);
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
            .withPair(
              playerIds[1],
              playerIds[2],
              DoubleState.redoubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[1],
              playerIds[3],
              DoubleState.doubled,
              initiator: playerIds[1],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
              chooserIndex: 0,
              doubles: matrix,
              onChanged: (m) => setState(() => matrix = m),
            ),
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        expect(find.widgetWithText(FilledButton, 'Slappe hap'), findsOneWidget);
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.none);
        expect(matrix.stateFor(playerIds[1], playerIds[3]), DoubleState.none);
      },
    );

    testWidgets(
      '"Slappe hap" from a partial state (chooser + 1 other doubled) transitions to Slappe hap',
      (tester) async {
        // chooser=2 (Carol), Bob(1) initiator. Bob has already doubled
        // chooser (1,2) and Alice (1,0). Pressing Slappe hap should
        // deselect the chooser pair and ensure Dan (1,3) is also doubled.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(
              playerIds[1],
              playerIds[2],
              DoubleState.doubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[1],
              playerIds[0],
              DoubleState.doubled,
              initiator: playerIds[1],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
        expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.none);
        expect(
          matrix.stateFor(playerIds[1], playerIds[0]),
          DoubleState.doubled,
        );
        expect(
          matrix.stateFor(playerIds[1], playerIds[3]),
          DoubleState.doubled,
        );
        expect(find.widgetWithText(FilledButton, 'Slappe hap'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Zaal'), findsOneWidget);
      },
    );

    testWidgets(
      '"Slappe hap" transition demotes a redoubled chooser pair instead of clearing it',
      (tester) async {
        // chooser=2, Bob(1) initiator. (1,2) is redoubled (Carol redoubled
        // Bob's double). Pressing Slappe hap should demote (1,2) to doubled
        // (initiator=Carol) and double the others.
        DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[1],
          playerIds[2],
          DoubleState.redoubled,
          initiator: playerIds[2],
        );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
        expect(
          matrix.stateFor(playerIds[1], playerIds[2]),
          DoubleState.doubled,
        );
        expect(matrix.initiatorFor(playerIds[1], playerIds[2]), playerIds[2]);
        expect(
          matrix.stateFor(playerIds[1], playerIds[0]),
          DoubleState.doubled,
        );
        expect(
          matrix.stateFor(playerIds[1], playerIds[3]),
          DoubleState.doubled,
        );
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
            players: players,
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
      expect(matrix.stateFor(playerIds[1], playerIds[0]), DoubleState.doubled);
      expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.doubled);
      expect(matrix.stateFor(playerIds[1], playerIds[3]), DoubleState.doubled);
      // Re-press clears all.
      await tester.tap(find.text('Zaal'));
      await tester.pump();
      expect(matrix.stateFor(playerIds[1], playerIds[0]), DoubleState.none);
      expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.none);
      expect(matrix.stateFor(playerIds[1], playerIds[3]), DoubleState.none);
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
              players: players,
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
        expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.none);
        expect(
          matrix.stateFor(playerIds[1], playerIds[0]),
          DoubleState.doubled,
        );
        expect(
          matrix.stateFor(playerIds[1], playerIds[3]),
          DoubleState.doubled,
        );
        // Now Slappe hap is filled, Zaal is outlined.
        expect(find.widgetWithText(FilledButton, 'Slappe hap'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Zaal'), findsOneWidget);
      },
    );

    testWidgets(
      '"Zaal terug" re-press demotes redoubles back to doubled, preserving initiator',
      (tester) async {
        // chooser=0 (Alice). All 3 others doubled Alice.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(
              playerIds[0],
              playerIds[1],
              DoubleState.doubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[0],
              playerIds[2],
              DoubleState.doubled,
              initiator: playerIds[2],
            )
            .withPair(
              playerIds[0],
              playerIds[3],
              DoubleState.doubled,
              initiator: playerIds[3],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
          expect(
            matrix.stateFor(playerIds[0], playerIds[t]),
            DoubleState.redoubled,
          );
        }
        // Now button should be filled.
        expect(find.widgetWithText(FilledButton, 'Zaal terug'), findsOneWidget);
        // Re-press: redoubles demote to doubled, original initiators kept;
        // doubles are NOT cleared.
        await tester.tap(find.text('Zaal terug'));
        await tester.pump();
        for (final t in [1, 2, 3]) {
          expect(
            matrix.stateFor(playerIds[0], playerIds[t]),
            DoubleState.doubled,
          );
          expect(matrix.initiatorFor(playerIds[0], playerIds[t]), playerIds[t]);
        }
      },
    );

    testWidgets(
      '"Slappe hap" stays outlined when a target doubled the initiator but no redouble back',
      (tester) async {
        // chooser=0. Bob(1) initiator. Carol(2) doubled Bob — pair is
        // doubled, initiator=Carol. Bob hasn't acted on Carol yet, so
        // Slappe hap should be outlined (not filled).
        final DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[1],
          playerIds[2],
          DoubleState.doubled,
          initiator: playerIds[2],
        );
        await pumpHost(
          tester,
          DoublesPicker(
            players: players,
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
        final DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(
              playerIds[1],
              playerIds[2],
              DoubleState.redoubled,
              initiator: playerIds[2],
            )
            .withPair(
              playerIds[1],
              playerIds[3],
              DoubleState.doubled,
              initiator: playerIds[1],
            );
        await pumpHost(
          tester,
          DoublesPicker(
            players: players,
            chooserIndex: 0,
            doubles: matrix,
            onChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        expect(find.widgetWithText(FilledButton, 'Slappe hap'), findsOneWidget);
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
            .withPair(
              playerIds[1],
              playerIds[0],
              DoubleState.redoubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[1],
              playerIds[2],
              DoubleState.doubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[1],
              playerIds[3],
              DoubleState.redoubled,
              initiator: playerIds[1],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
          expect(matrix.stateFor(playerIds[1], playerIds[t]), DoubleState.none);
        }
      },
    );

    testWidgets(
      '"Terug op beide" — chooser doubled by exactly 2 → bulk redouble those two',
      (tester) async {
        // chooser=2 (Carol). Alice and Dan doubled Carol; Bob did not.
        DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(
              playerIds[2],
              playerIds[0],
              DoubleState.doubled,
              initiator: playerIds[0],
            )
            .withPair(
              playerIds[2],
              playerIds[3],
              DoubleState.doubled,
              initiator: playerIds[3],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
        expect(
          matrix.stateFor(playerIds[2], playerIds[0]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[2], playerIds[0]), playerIds[0]);
        expect(
          matrix.stateFor(playerIds[2], playerIds[3]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[2], playerIds[3]), playerIds[3]);
        // Bob's pair untouched.
        expect(matrix.stateFor(playerIds[2], playerIds[1]), DoubleState.none);
        // Now filled.
        expect(
          find.widgetWithText(FilledButton, 'Terug op beide'),
          findsOneWidget,
        );
        // Re-press demotes back to doubled with original initiators.
        await tester.tap(find.text('Terug op beide'));
        await tester.pump();
        expect(
          matrix.stateFor(playerIds[2], playerIds[0]),
          DoubleState.doubled,
        );
        expect(matrix.initiatorFor(playerIds[2], playerIds[0]), playerIds[0]);
        expect(
          matrix.stateFor(playerIds[2], playerIds[3]),
          DoubleState.doubled,
        );
        expect(matrix.initiatorFor(playerIds[2], playerIds[3]), playerIds[3]);
      },
    );

    testWidgets(
      '"Terug op beide" outlined when only one of the two doublers has been redoubled',
      (tester) async {
        // chooser=2. Alice doubled; Dan doubled then Carol redoubled Dan.
        final DoubleMatrix matrix = DoubleMatrix.empty()
            .withPair(
              playerIds[2],
              playerIds[0],
              DoubleState.doubled,
              initiator: playerIds[0],
            )
            .withPair(
              playerIds[2],
              playerIds[3],
              DoubleState.redoubled,
              initiator: playerIds[3],
            );
        await pumpHost(
          tester,
          DoublesPicker(
            players: players,
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
        final DoubleMatrix matrix = DoubleMatrix.empty().withPair(
          playerIds[2],
          playerIds[0],
          DoubleState.doubled,
          initiator: playerIds[0],
        );
        await pumpHost(
          tester,
          DoublesPicker(
            players: players,
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
            .withPair(
              playerIds[1],
              playerIds[0],
              DoubleState.doubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[1],
              playerIds[2],
              DoubleState.redoubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[1],
              playerIds[3],
              DoubleState.doubled,
              initiator: playerIds[1],
            );
        await pumpHost(
          tester,
          StatefulBuilder(
            builder: (ctx, setState) => DoublesPicker(
              players: players,
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
        expect(matrix.stateFor(playerIds[1], playerIds[2]), DoubleState.none);
        expect(
          matrix.stateFor(playerIds[1], playerIds[0]),
          DoubleState.doubled,
        );
        expect(
          matrix.stateFor(playerIds[1], playerIds[3]),
          DoubleState.doubled,
        );
      },
    );

    testWidgets('bulk action buttons honour the 48dp touch-target floor that '
        'matches the surrounding tile rhythm', (tester) async {
      // chooser=2, Carol initiator with one doubled target → "Zaal"
      // and "Slappe hap" both rendered. Pick whichever button shows.
      final DoubleMatrix matrix = DoubleMatrix.empty().withPair(
        playerIds[2],
        playerIds[0],
        DoubleState.doubled,
        initiator: playerIds[0],
      );
      await pumpHost(
        tester,
        DoublesPicker(
          players: players,
          chooserIndex: 2,
          doubles: matrix,
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.text('Carol').first);
      await tester.pump();

      // Both bulk buttons should clear the 48dp minimum height.
      for (final label in ['Zaal', 'Slappe hap']) {
        final size = tester.getSize(find.text(label).hitTestable());
        // Sanity: text widget itself is the inner child of the button;
        // measure the button instead.
        final button = find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (w) => w is OutlinedButton || w is FilledButton,
              ),
            )
            .first;
        final btnSize = tester.getSize(button);
        expect(
          btnSize.height,
          greaterThanOrEqualTo(48),
          reason:
              '"$label" button height ${btnSize.height} < 48dp '
              '(tile rhythm broken); text size was $size',
        );
      }
    });
  });
}
