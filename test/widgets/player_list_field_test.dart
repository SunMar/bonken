import 'package:bonken/widgets/player_list_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('PlayerListField', () {
    late List<TextEditingController> controllers;
    late List<FocusNode> focusNodes;

    setUp(() {
      controllers = List.generate(4, (_) => TextEditingController());
      focusNodes = List.generate(4, (_) => FocusNode());
    });

    Future<void> teardown(WidgetTester tester) async {
      // Detach widgets first so FocusNodes are no longer attached to the
      // tree before we dispose them.
      await tester.pumpWidget(const SizedBox.shrink());
      for (final c in controllers) {
        c.dispose();
      }
      for (final n in focusNodes) {
        n.dispose();
      }
    }

    Widget host({void Function(int, int)? onReorderItem}) => StatefulBuilder(
      builder: (context, setState) {
        // Mimic NewGameScreen: rebuild on every keystroke so the
        // duplicate warning reflects the latest controller text.
        for (final c in controllers) {
          c
            ..removeListener(() {})
            ..addListener(() {
              if (context.mounted) setState(() {});
            });
        }
        return PlayerListField(
          controllers: controllers,
          focusNodes: focusNodes,
          suggestions: const [],
          onReorderItem: (oldI, newI) {
            // onReorderItem already pre-adjusts newI — no decrement here.
            setState(() {
              final c = controllers.removeAt(oldI);
              controllers.insert(newI, c);
              final f = focusNodes.removeAt(oldI);
              focusNodes.insert(newI, f);
            });
            onReorderItem?.call(oldI, newI);
          },
          onSubmitted: (_) {},
        );
      },
    );

    testWidgets('renders 4 input rows', (tester) async {
      await pumpHost(tester, host());
      expect(find.byType(TextField), findsNWidgets(4));
      await teardown(tester);
    });

    testWidgets('no duplicate warning when names are unique', (tester) async {
      await pumpHost(tester, host());
      for (int i = 0; i < 4; i++) {
        await tester.enterText(find.byType(TextField).at(i), playerNames[i]);
      }
      await tester.pump();
      expect(find.text('Twee spelers hebben dezelfde naam.'), findsNothing);
      await teardown(tester);
    });

    testWidgets('shows duplicate warning on case-insensitive collision', (
      tester,
    ) async {
      await pumpHost(tester, host());
      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      await tester.enterText(find.byType(TextField).at(1), 'alice');
      await tester.pump();
      expect(find.text('Twee spelers hebben dezelfde naam.'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('warning ignores empty slots', (tester) async {
      await pumpHost(tester, host());
      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      // slots 1..3 left empty — two empties shouldn't trigger the warning
      await tester.pump();
      expect(find.text('Twee spelers hebben dezelfde naam.'), findsNothing);
      await teardown(tester);
    });

    testWidgets('onReorderItem re-keys rows so text follows the moved row', (
      tester,
    ) async {
      await pumpHost(tester, host());
      for (int i = 0; i < 4; i++) {
        await tester.enterText(find.byType(TextField).at(i), playerNames[i]);
      }
      await tester.pump();

      // Move Carol (slot 2) to the front. The host moves the controller +
      // focus node and rebuilds; the row's ValueKey(focusNode) keeps the text
      // bound to the moved row.
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(2, 0);
      await tester.pump();

      final texts = [
        for (int i = 0; i < 4; i++)
          tester
              .widget<TextField>(find.byType(TextField).at(i))
              .controller!
              .text,
      ];
      expect(texts, ['Carol', 'Alice', 'Bob', 'Dan']);
      await teardown(tester);
    });

    testWidgets('duplicate warning persists across a reorder', (tester) async {
      await pumpHost(tester, host());
      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      await tester.enterText(find.byType(TextField).at(1), 'alice');
      await tester.pump();
      expect(find.text('Twee spelers hebben dezelfde naam.'), findsOneWidget);

      // Reorder one of the colliding rows away; the warning is text-derived, so
      // it must still show after the rebuild.
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(1, 3);
      await tester.pump();
      expect(find.text('Twee spelers hebben dezelfde naam.'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('asserts when controllers/focusNodes have wrong length', (
      tester,
    ) async {
      expect(
        () => PlayerListField(
          controllers: [TextEditingController()],
          focusNodes: [FocusNode()],
          suggestions: const [],
          onReorderItem: (_, _) {},
          onSubmitted: (_) {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('DealerDropdownField', () {
    late List<TextEditingController> controllers;

    setUp(() {
      controllers = [
        for (final n in playerNames) TextEditingController(text: n),
      ];
    });

    tearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });

    testWidgets('uses controller text as labels (with fallback)', (
      tester,
    ) async {
      controllers[2].text = ''; // Carol slot empty
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: null,
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.byType(DealerDropdownField));
      await tester.pumpAndSettle();
      // Alice/Bob/Dan show their controller text; slot 2 falls back to "Speler 3"
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Speler 3'), findsWidgets);
      expect(find.text('Dan'), findsWidgets);
    });

    testWidgets('onChanged fires with picked index', (tester) async {
      int? picked;
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: null,
          onChanged: (v) => picked = v,
        ),
      );
      await tester.tap(find.byType(DealerDropdownField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol').last);
      await tester.pumpAndSettle();
      expect(picked, 2);
    });

    testWidgets('"Willekeurige deler" entry only present when '
        'allowRandomDealer is true', (tester) async {
      // Case 1: default (allowRandomDealer:false) → entry absent.
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: null,
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.byType(DealerDropdownField));
      await tester.pumpAndSettle();
      expect(find.text('Willekeurige deler'), findsNothing);
      // Close the menu before pumping the next case.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Case 2: allowRandomDealer:true → entry present, picking it
      // reports null via onChanged.
      int? lastPick = -999;
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: null,
          allowRandomDealer: true,
          onChanged: (v) => lastPick = v,
        ),
      );
      await tester.tap(find.byType(DealerDropdownField));
      await tester.pumpAndSettle();
      expect(find.text('Willekeurige deler'), findsWidgets);
      await tester.tap(find.text('Willekeurige deler').last);
      await tester.pumpAndSettle();
      expect(lastPick, isNull);
    });

    testWidgets('exposes its purpose label to assistive tech', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: 1,
          onChanged: (_) {},
        ),
      );
      // The field otherwise announces only its current value; the Semantics
      // wrapper adds the section purpose ("Deler eerste ronde").
      expect(
        find.bySemanticsLabel(RegExp(kDealerSectionTitle)),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('displayed selection follows an external value change '
        '(no ValueKey rebuild needed)', (tester) async {
      TextField field() => tester.widget<TextField>(
        find.descendant(
          of: find.byType(DropdownMenu<int>),
          matching: find.byType(TextField),
        ),
      );

      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: 0,
          onChanged: (_) {},
        ),
      );
      expect(field().controller!.text, 'Alice');

      // Rebuild the same (keyless) field with a new value; DropdownMenu
      // re-seeds its displayed label from initialSelection.
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: 2,
          onChanged: (_) {},
        ),
      );
      expect(field().controller!.text, 'Carol');
    });
  });

  group('handlePlayerFieldSubmitted', () {
    late List<TextEditingController> controllers;
    late List<FocusNode> focusNodes;

    setUp(() {
      controllers = List.generate(4, (_) => TextEditingController());
      focusNodes = List.generate(4, (_) => FocusNode());
    });

    tearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
      for (final n in focusNodes) {
        n.dispose();
      }
    });

    testWidgets('focuses next empty slot', (tester) async {
      // Need to attach focus nodes to a tree before they can take focus.
      await pumpHost(
        tester,
        Column(
          children: [
            for (int i = 0; i < 4; i++)
              TextField(controller: controllers[i], focusNode: focusNodes[i]),
          ],
        ),
      );
      controllers[0].text = 'Alice';
      handlePlayerFieldSubmitted(
        index: 0,
        controllers: controllers,
        focusNodes: focusNodes,
      );
      await tester.pump();
      expect(focusNodes[1].hasFocus, isTrue);
    });

    testWidgets('unfocuses current when next slot is non-empty', (
      tester,
    ) async {
      await pumpHost(
        tester,
        Column(
          children: [
            for (int i = 0; i < 4; i++)
              TextField(controller: controllers[i], focusNode: focusNodes[i]),
          ],
        ),
      );
      controllers[0].text = 'Alice';
      controllers[1].text = 'Bob';
      focusNodes[0].requestFocus();
      await tester.pump();
      expect(focusNodes[0].hasFocus, isTrue);

      handlePlayerFieldSubmitted(
        index: 0,
        controllers: controllers,
        focusNodes: focusNodes,
      );
      await tester.pump();
      expect(focusNodes[0].hasFocus, isFalse);
      expect(focusNodes[1].hasFocus, isFalse);
    });

    testWidgets('unfocuses last slot (no next)', (tester) async {
      await pumpHost(
        tester,
        Column(
          children: [
            for (int i = 0; i < 4; i++)
              TextField(controller: controllers[i], focusNode: focusNodes[i]),
          ],
        ),
      );
      focusNodes[3].requestFocus();
      await tester.pump();
      expect(focusNodes[3].hasFocus, isTrue);

      handlePlayerFieldSubmitted(
        index: 3,
        controllers: controllers,
        focusNodes: focusNodes,
      );
      await tester.pump();
      expect(focusNodes[3].hasFocus, isFalse);
    });
  });
}
