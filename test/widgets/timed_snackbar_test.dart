// Tests for [showTimedSnackBar]: it hides any current snackbar, shows the
// new one, and force-closes it after its duration — 4 s without an action,
// 6 s with one (actionable snackbars stay longer so users can act).

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
  testWidgets('shows the snackbar and force-closes after duration', (
    tester,
  ) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('hello'));
    await tester.pump(); // start show animation
    expect(find.text('hello'), findsOneWidget);

    // Just before 4 s elapses it should still be visible.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('hello'), findsOneWidget);

    // After 4 s the Timer fires; let the close animation finish.
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

    // Drain the second snackbar's timer. The first call's timer was
    // cancelled by the second call, so only one timer is pending here.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('actionable snackbar stays 6 s; plain one 4 s', (tester) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('plain'));
    await tester.pump();
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 4),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    showTimedSnackBar(
      messenger,
      content: const Text('with action'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pump();
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 6),
    );
    await tester.pumpAndSettle(const Duration(seconds: 7));
  });

  testWidgets('always shows close icon and floating behavior', (tester) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, content: const Text('test'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.showCloseIcon, isTrue);
    expect(snackBar.behavior, SnackBarBehavior.floating);

    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
