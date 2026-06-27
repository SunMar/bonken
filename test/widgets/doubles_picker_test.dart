import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:bonken/widgets/doubles_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
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
          doubles: const DoubleMatrix(),
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
          doubles: const DoubleMatrix(),
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
          doubles: const DoubleMatrix(),
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
        DoubleMatrix matrix = const DoubleMatrix();
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
      DoubleMatrix matrix = const DoubleMatrix()
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
        DoubleMatrix matrix = const DoubleMatrix()
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
      DoubleMatrix matrix = const DoubleMatrix();
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
          doubles: const DoubleMatrix(),
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
      'forceable target tile reads disabled with a "Forceren" custom action',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpHost(
          tester,
          DoublesPicker(
            players: players,
            chooserIndex: 0, // Alice is the chooser.
            doubles: const DoubleMatrix(),
            onChanged: (_) {},
          ),
        );

        // With no initiator selected, target rows are truly inert: presented to
        // assistive tech as disabled, with no override hint.
        expect(
          tester.getSemantics(find.text('Bob').last),
          isSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hint: '',
          ),
        );

        // Select the chooser → the Bob target becomes a dimmed-but-tappable
        // override. Post-fix it is presented as *disabled* (matching its dimmed
        // look, so WCAG contrast-exempt) but carries the 'Forceren' custom
        // action + the override hint so a screen-reader user can still force it.
        await tester.tap(find.text('Alice').first);
        await tester.pump();

        expect(
          tester.getSemantics(find.text('Bob').last),
          isSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hint: 'Normaal niet toegestaan; activeer om te forceren',
            customActions: const [CustomSemanticsAction(label: 'Forceren')],
          ),
        );

        handle.dispose();
      },
    );

    testWidgets(
      'chooser initiating can be forced via "Toch dubbelen"; re-tap clears it',
      (tester) async {
        DoubleMatrix matrix = const DoubleMatrix();
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
        DoubleMatrix matrix = const DoubleMatrix().withPair(
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
      DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        DoubleMatrix matrix = const DoubleMatrix();
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
        DoubleMatrix matrix = const DoubleMatrix()
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
      '"Slappe hap" re-press demotes a foreign-initiated redouble to doubled '
      '(not none)',
      (tester) async {
        // chooser=0 (Alice). Initiator Dan(3) (turn after Bob, so he may go
        // back). Bob(1) has already doubled Dan — a FOREIGN double on the
        // Bob–Dan pair (initiator=Bob). Dan's Slappe hap escalates that pair to
        // redoubled and doubles Carol(2); re-pressing must demote the Bob–Dan
        // pair back to Bob's double — NOT wipe it (the bug was clearing to none).
        DoubleMatrix matrix = const DoubleMatrix().withPair(
          playerIds[3],
          playerIds[1],
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
        await tester.tap(find.text('Dan').first);
        await tester.pump();

        // First press: Dan doubles Carol and redoubles on Bob's double.
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(
          matrix.stateFor(playerIds[3], playerIds[1]),
          DoubleState.redoubled,
        );
        expect(matrix.initiatorFor(playerIds[3], playerIds[1]), playerIds[1]);
        expect(
          matrix.stateFor(playerIds[3], playerIds[2]),
          DoubleState.doubled,
        );

        // Re-press: only Dan's contributions are undone — Bob's double on Dan
        // survives (demoted from redoubled to doubled), Dan's own double clears.
        await tester.tap(find.text('Slappe hap'));
        await tester.pump();
        expect(
          matrix.stateFor(playerIds[3], playerIds[1]),
          DoubleState.doubled,
        );
        expect(matrix.initiatorFor(playerIds[3], playerIds[1]), playerIds[1]);
        expect(matrix.stateFor(playerIds[3], playerIds[2]), DoubleState.none);
      },
    );

    testWidgets(
      '"Slappe hap" from a partial state (chooser + 1 other doubled) transitions to Slappe hap',
      (tester) async {
        // chooser=2 (Carol), Bob(1) initiator. Bob has already doubled
        // chooser (1,2) and Alice (1,0). Pressing Slappe hap should
        // deselect the chooser pair and ensure Dan (1,3) is also doubled.
        DoubleMatrix matrix = const DoubleMatrix()
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
        DoubleMatrix matrix = const DoubleMatrix().withPair(
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
      DoubleMatrix matrix = const DoubleMatrix();
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

    testWidgets('bulk buttons convey applied state via toggled semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      DoubleMatrix matrix = const DoubleMatrix();
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (ctx, setState) => DoublesPicker(
            players: players,
            chooserIndex: 2, // Bob(1) initiator → "Zaal" doubles all others
            doubles: matrix,
            onChanged: (m) => setState(() => matrix = m),
          ),
        ),
      );
      await tester.tap(find.text('Bob').first);
      await tester.pump();
      // Not yet applied → toggle state present but off.
      expect(
        tester.getSemantics(find.text('Zaal')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      // Applied → toggled on (re-pressing would undo it).
      await tester.tap(find.text('Zaal'));
      await tester.pump();
      expect(
        tester.getSemantics(find.text('Zaal')),
        isSemantics(isToggled: true),
      );
      handle.dispose();
    });

    testWidgets(
      'when "Zaal" is applied, "Slappe hap" is outlined; pressing it clears the chooser pair',
      (tester) async {
        // chooser=2 (Carol). Bob(1) initiator. Apply Zaal → all 3 doubled.
        DoubleMatrix matrix = const DoubleMatrix();
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
        DoubleMatrix matrix = const DoubleMatrix()
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
        final DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        final DoubleMatrix matrix = const DoubleMatrix()
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
        DoubleMatrix matrix = const DoubleMatrix()
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
        DoubleMatrix matrix = const DoubleMatrix()
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
        final DoubleMatrix matrix = const DoubleMatrix()
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
        final DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        DoubleMatrix matrix = const DoubleMatrix()
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
      final DoubleMatrix matrix = const DoubleMatrix().withPair(
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

    testWidgets(
      'non-initiator target shows "is gedubbeld door" then "gaat terug op"',
      (tester) async {
        // Alice doubled Bob (Alice initiated). chooser = Dan(3): order is
        // Alice→Bob→Carol→Dan, so Bob's turn (1) is after Alice's (0) → Bob may
        // redouble.
        DoubleMatrix matrix = const DoubleMatrix().withPair(
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
        // Select Bob (the doubled-upon side) → his Alice target reads the
        // received-double direction label.
        await tester.tap(find.text('Bob').first);
        await tester.pump();
        expect(find.text('is gedubbeld door'), findsOneWidget);
        // Bob goes back on Alice → the label flips to the redouble direction.
        await tester.tap(find.text('Alice').last);
        await tester.pump();
        expect(find.text('gaat terug op'), findsOneWidget);
      },
    );

    testWidgets(
      'initiator target shows "dubbelt" then adds "gaat terug" chips',
      (tester) async {
        // chooser = Carol(2): order Dan→Alice→Bob→Carol. Dan(turn 0) doubles
        // Carol(turn 3, later) → may escalate to redoubled.
        DoubleMatrix matrix = const DoubleMatrix();
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
        await tester.tap(find.text('Dan').first);
        await tester.pump();
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(find.text('dubbelt'), findsOneWidget);
        expect(find.text('gaat terug'), findsNothing);
        // Redouble → the tile shows both the "dubbelt" and "gaat terug" chips.
        await tester.tap(find.text('Carol').last);
        await tester.pump();
        expect(find.text('dubbelt'), findsOneWidget);
        expect(find.text('gaat terug'), findsOneWidget);
      },
    );

    testWidgets(
      'initiator badge: count, doubled/redoubled tint, pluralised a11y label',
      (tester) async {
        final handle = tester.ensureSemantics();
        late DoubleStateColors dc;
        // Alice is in 2 pairs (one redoubled by Bob, one doubled on Carol).
        final matrix = const DoubleMatrix()
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
              initiator: playerIds[0],
            );
        await pumpHost(
          tester,
          Builder(
            builder: (ctx) {
              dc = DoubleStateColors.of(ctx);
              return DoublesPicker(
                players: players,
                chooserIndex: 3,
                doubles: matrix,
                onChanged: (_) {},
              );
            },
          ),
        );

        // Alice is in 2 pairs → badge "2", with the redoubled tint (she has a
        // redoubled pair). _involvedCount skips the self pair.
        final aliceBadge = tester.widget<Badge>(
          find.ancestor(of: find.text('2'), matching: find.byType(Badge)),
        );
        expect(aliceBadge.backgroundColor, dc.redoubledBackground);

        // Both tints appear across the badges (Carol's pair is doubled-only).
        final tints = tester
            .widgetList<Badge>(find.byType(Badge))
            .map((b) => b.backgroundColor)
            .toSet();
        expect(
          tints,
          containsAll(<Color?>[dc.doubledBackground, dc.redoubledBackground]),
        );

        // a11y label pluralises: Alice "2 dubbels"; the two count-1 players
        // (Bob, Carol) each read "1 dubbel".
        expect(
          find.bySemanticsLabel(RegExp('betrokken bij 2 dubbels')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'betrokken bij 1 dubbel\b')),
          findsNWidgets(2),
        );
        handle.dispose();
      },
    );

    testWidgets('targets are disabled before any initiator is selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        DoublesPicker(
          players: players,
          chooserIndex: 0,
          doubles: const DoubleMatrix(),
          onChanged: (_) {},
        ),
      );
      // With nothing selected, every target row is inert — disabled to AT, so
      // `_selected!` is never dereferenced without a selection.
      expect(
        tester.getSemantics(find.text('Bob').last),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets(
      '"Zaal terug" stays outlined when only 2 of 3 doublers are redoubled',
      (tester) async {
        // chooser = Alice(0), doubled by all three others; two redoubled, one
        // still only doubled → the bulk redouble is not yet fully applied.
        final matrix = const DoubleMatrix()
            .withPair(
              playerIds[0],
              playerIds[1],
              DoubleState.redoubled,
              initiator: playerIds[1],
            )
            .withPair(
              playerIds[0],
              playerIds[2],
              DoubleState.redoubled,
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
          DoublesPicker(
            players: players,
            chooserIndex: 0,
            doubles: matrix,
            onChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Alice').first);
        await tester.pump();
        // 3 doublers → "Zaal terug" label; not all redoubled → outlined.
        expect(
          find.widgetWithText(OutlinedButton, 'Zaal terug'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Zaal terug'), findsNothing);
      },
    );
  });
}
