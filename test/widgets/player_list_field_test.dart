import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/widgets/player_list_field.dart';

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

    Widget host({void Function(int, int)? onReorder}) => StatefulBuilder(
      builder: (context, setState) {
        // Mimic SetupScreen: rebuild on every keystroke so the
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
          onReorder: (oldI, newI) {
            var t = newI;
            if (t > oldI) t -= 1;
            setState(() {
              final c = controllers.removeAt(oldI);
              controllers.insert(t, c);
              final f = focusNodes.removeAt(oldI);
              focusNodes.insert(t, f);
            });
            onReorder?.call(oldI, newI);
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

    testWidgets('shows duplicate warning on case-insensitive collision',
        (tester) async {
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

    testWidgets('asserts when controllers/focusNodes have wrong length',
        (tester) async {
      expect(
        () => PlayerListField(
          controllers: [TextEditingController()],
          focusNodes: [FocusNode()],
          suggestions: const [],
          onReorder: (_, _) {},
          onSubmitted: (_) {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('DealerDropdownField', () {
    late List<TextEditingController> controllers;

    setUp(() {
      controllers = [for (final n in playerNames) TextEditingController(text: n)];
    });

    tearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });

    testWidgets('uses controller text as labels (with fallback)',
        (tester) async {
      controllers[2].text = ''; // Carol slot empty
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: null,
          onChanged: (_) {},
          hintText: 'Pick',
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
          hintText: 'Pick',
        ),
      );
      await tester.tap(find.byType(DealerDropdownField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol').last);
      await tester.pumpAndSettle();
      expect(picked, 2);
    });

    testWidgets('clear (X) button only shown when value!=null AND onClear given',
        (tester) async {
      // Case 1: value=null → no X
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: null,
          onChanged: (_) {},
          onClear: () {},
        ),
      );
      expect(find.byTooltip('Wissen (willekeurige deler)'), findsNothing);

      // Case 2: value=2 but no onClear → no X
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: 2,
          onChanged: (_) {},
        ),
      );
      expect(find.byTooltip('Wissen (willekeurige deler)'), findsNothing);

      // Case 3: value=2 AND onClear → X visible
      bool cleared = false;
      await pumpHost(
        tester,
        DealerDropdownField(
          controllers: controllers,
          value: 2,
          onChanged: (_) {},
          onClear: () => cleared = true,
        ),
      );
      expect(find.byTooltip('Wissen (willekeurige deler)'), findsOneWidget);
      await tester.tap(find.byTooltip('Wissen (willekeurige deler)'));
      expect(cleared, isTrue);
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

    testWidgets('unfocuses current when next slot is non-empty', (tester) async {
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
