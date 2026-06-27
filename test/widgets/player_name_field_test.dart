import 'package:bonken/models/game_constraints.dart';
import 'package:bonken/widgets/player_name_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

/// Returns the visible suggestion strings from the autocomplete dropdown,
/// or an empty list when the dropdown isn't shown.
List<String> visibleSuggestions(WidgetTester tester) {
  final inkwells = find.descendant(
    of: find.byType(Material).last,
    matching: find.byType(InkWell),
  );
  return inkwells.evaluate().map((e) {
    final iw = e.widget as InkWell;
    final text = (iw.child as Padding).child as Text;
    return text.data ?? '';
  }).toList();
}

void main() {
  group('PlayerNameField — autocomplete', () {
    testWidgets(
      'case-insensitive: takenNames hides Alice, Bob remains; "ali" hides all',
      (tester) async {
        final controller = TextEditingController();
        final focus = FocusNode();
        await pumpHost(
          tester,
          PlayerNameField(
            index: 0,
            controller: controller,
            focusNode: focus,
            suggestions: const ['Alice', 'Bob'],
            takenNames: const {'alice'},
            onSubmitted: () {},
            isLast: true,
          ),
        );

        // Focus the field with empty query — only Bob should remain
        // (Alice is filtered case-insensitively by takenNames).
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        var visible = visibleSuggestions(tester);
        expect(visible, ['Bob']);

        // Type "ali" — Alice would match, but is hidden by takenNames.
        await tester.enterText(find.byType(TextField), 'ali');
        await tester.pumpAndSettle();
        visible = visibleSuggestions(tester);
        expect(visible, isEmpty);

        controller.dispose();
        focus.dispose();
      },
    );
  });

  group('PlayerNameField — keyboard & limits', () {
    testWidgets('Tab fires onSubmitted and does not auto-pick a suggestion', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      var submitted = 0;
      await pumpHost(
        tester,
        PlayerNameField(
          index: 0,
          controller: controller,
          focusNode: focus,
          suggestions: const ['Alice', 'Bob'],
          takenNames: const {},
          onSubmitted: () => submitted++,
          isLast: false,
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(submitted, 1);
      // The highlighted suggestion (Alice) must NOT be auto-filled — Tab keeps
      // exactly what the user typed (a documented design choice).
      expect(controller.text, 'al');

      controller.dispose();
      focus.dispose();
    });

    testWidgets('tapping a suggestion fills the field', (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      await pumpHost(
        tester,
        PlayerNameField(
          index: 0,
          controller: controller,
          focusNode: focus,
          suggestions: const ['Alice', 'Bob'],
          takenNames: const {},
          onSubmitted: () {},
          isLast: true,
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'al');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(controller.text, 'Alice');

      controller.dispose();
      focus.dispose();
    });

    testWidgets('input is capped at kPlayerNameMaxLength characters', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      await pumpHost(
        tester,
        PlayerNameField(
          index: 0,
          controller: controller,
          focusNode: focus,
          suggestions: const [],
          takenNames: const {},
          onSubmitted: () {},
          isLast: true,
        ),
      );

      await tester.enterText(
        find.byType(TextField),
        'x' * (kPlayerNameMaxLength + 10),
      );
      await tester.pump();

      expect(controller.text.length, kPlayerNameMaxLength);

      controller.dispose();
      focus.dispose();
    });
  });
}
