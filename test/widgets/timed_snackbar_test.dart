// Tests for [showTimedSnackBar]: it hides any current snackbar, shows the
// new one, and force-closes it after the SnackBar's [duration] elapses.

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

    showTimedSnackBar(
      messenger,
      const SnackBar(content: Text('hello'), duration: Duration(seconds: 2)),
    );
    await tester.pump(); // start show animation
    expect(find.text('hello'), findsOneWidget);

    // Just before duration elapses it should still be visible.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('hello'), findsOneWidget);

    // After the duration + close animation, the snackbar is gone.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('hides the current snackbar before showing the next one', (
    tester,
  ) async {
    final messenger = await _pumpMessenger(tester);

    showTimedSnackBar(messenger, const SnackBar(content: Text('first')));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    showTimedSnackBar(messenger, const SnackBar(content: Text('second')));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    // Drain the second snackbar's timer. The first call's timer was
    // cancelled by the second call, so only one timer is pending here.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
