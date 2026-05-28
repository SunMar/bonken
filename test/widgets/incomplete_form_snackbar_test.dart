// Tests for [showIncompleteFormSnackBar]: thin wrapper around
// [showTimedSnackBar] used by save buttons that stay enabled so the user
// can learn *why* nothing happened.

import 'package:bonken/widgets/incomplete_form_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows the given message in a floating snackbar with a close icon',
    (tester) async {
      late ScaffoldMessengerState messenger;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                messenger = ScaffoldMessenger.of(ctx);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      showIncompleteFormSnackBar(messenger, message: 'Vul eerst alles in');
      await tester.pump();

      expect(find.text('Vul eerst alles in'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.showCloseIcon, isTrue);
      // No action button — there's nothing to undo.
      expect(snackBar.action, isNull);

      // Drain the internal Timer before the test ends.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
}
