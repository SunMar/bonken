// Tests for [showTimedSnackBar]: it hides any current snackbar, shows the
// new one, and lets the framework auto-dismiss it after its duration
// (`persist: false`) — 4 s without an action, 6 s with one (actionable
// snackbars stay longer so users can act).

import 'package:bonken/widgets/timed_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ScaffoldMessengerState> _pumpMessenger(WidgetTester tester) async {
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
  return messenger;
}

void main() {
  testWidgets('shows the snackbar and auto-dismisses after duration', (
    tester,
  ) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('hello'));
    // Finish the entrance: the framework schedules its dismiss timer only once
    // the bar is fully shown.
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);

    // Just before 4 s elapses it should still be visible.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('hello'), findsOneWidget);

    // After 4 s the framework auto-dismisses it; let the close animation finish.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('hides the current snackbar before showing the next one', (
    tester,
  ) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('first'));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    showTimedSnackBar(messenger, content: const Text('second'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    // Drain the second snackbar's framework auto-dismiss timer. Hiding the
    // first bar cancelled its timer, so only one is pending here.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('actionable snackbar stays 6 s; plain one 4 s', (tester) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('plain'));
    await tester.pumpAndSettle(); // entrance; framework schedules its 4 s timer
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 4),
    );
    // Fire the framework's dismiss timer, then finish the exit.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    showTimedSnackBar(
      messenger,
      content: const Text('with action'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pumpAndSettle(); // entrance; framework schedules its 6 s timer
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 6),
    );
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('always shows close icon and floating behavior', (tester) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('test'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.showCloseIcon, isTrue);
    expect(snackBar.behavior, SnackBarBehavior.floating);
    // persist:false ⇒ the framework auto-dismisses after duration even with an
    // action (Flutter 3.38+ otherwise keeps action snackbars on screen).
    expect(snackBar.persist, isFalse);

    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('manual dismiss leaves no pending auto-dismiss timer', (
    tester,
  ) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('dismiss me'));
    await tester.pumpAndSettle(); // finish the entrance animation
    expect(find.text('dismiss me'), findsOneWidget);

    // Dismiss via the always-present close icon, well before the 4 s duration.
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('dismiss me'), findsNothing);

    // No drain pump: the framework cancels its own dismiss timer when the bar
    // is hidden, so none survives to teardown. (A surviving timer would fail
    // with "A Timer is still pending".)
  });
}
