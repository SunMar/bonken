import 'package:bonken/widgets/selectable_player_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('SelectablePlayerTile semantics', () {
    testWidgets('unselected tile: button role, not selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        SelectablePlayerTile(
          name: 'Alice',
          isSelected: false,
          isDimmed: false,
          onTap: () {},
        ),
      );
      // MergeSemantics fuses the button flag, selected state, and the text label
      // into one node — find.bySemanticsLabel exercises this merged tree, not
      // just the widget hierarchy.
      final semantics = tester.getSemantics(find.bySemanticsLabel('Alice'));
      expect(
        semantics,
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          // hasSelectedState is set whenever Semantics(selected:) is used,
          // even when isSelected is false — it signals that this widget
          // participates in the selection model.
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('selected tile: button role, is selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        SelectablePlayerTile(
          name: 'Alice',
          isSelected: true,
          isDimmed: false,
          onTap: () {},
        ),
      );
      final semantics = tester.getSemantics(find.bySemanticsLabel('Alice'));
      expect(
        semantics,
        matchesSemantics(
          isButton: true,
          isSelected: true,
          isFocusable: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('dimmed tile: presented as disabled with a Selecteren action — '
        'opacity is visual only', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        SelectablePlayerTile(
          name: 'Alice',
          isSelected: false,
          isDimmed: true,
          onTap: () {},
        ),
      );
      // Dimmed → announced disabled (so the 38%-opacity text is WCAG
      // contrast-exempt), but the switch stays reachable via a custom action.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Alice')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
          isSelected: false,
          customActions: const [CustomSemanticsAction(label: 'Selecteren')],
        ),
      );
      handle.dispose();
    });

    testWidgets('badge slot renders the trailing badge after the name', (
      tester,
    ) async {
      await pumpHost(
        tester,
        SelectablePlayerTile(
          name: 'Alice',
          isSelected: false,
          isDimmed: false,
          onTap: () {},
          badge: const Badge(label: Text('3')),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}
