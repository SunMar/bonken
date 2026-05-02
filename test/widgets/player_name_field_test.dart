import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/widgets/player_name_field.dart';

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
}
