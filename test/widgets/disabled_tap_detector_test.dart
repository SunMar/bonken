import 'package:bonken/widgets/disabled_tap_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('DisabledTapDetector', () {
    testWidgets('enabled: tapping fires onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        wrap(
          DisabledTapDetector(
            enabled: true,
            onTap: () => tapped++,
            child: const Text('child'),
          ),
        ),
      );

      // warnIfMissed: false because the GestureDetector overlay intercepts
      // the tap before the Text widget receives it — that is the intended
      // behaviour, not a misfire.
      await tester.tap(find.text('child'), warnIfMissed: false);
      expect(tapped, 1);
    });

    testWidgets('disabled: tapping does not fire onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        wrap(
          DisabledTapDetector(
            enabled: false,
            onTap: () => tapped++,
            child: const Text('child'),
          ),
        ),
      );

      await tester.tap(find.text('child'));
      expect(tapped, 0);
    });

    testWidgets('child renders in both enabled and disabled states', (
      tester,
    ) async {
      for (final enabled in [true, false]) {
        await tester.pumpWidget(
          wrap(
            DisabledTapDetector(
              enabled: enabled,
              onTap: () {},
              child: const Text('child'),
            ),
          ),
        );
        expect(find.text('child'), findsOneWidget);
      }
    });

    testWidgets('enabled: overlay is excluded from semantics', (tester) async {
      await tester.pumpWidget(
        wrap(
          DisabledTapDetector(
            enabled: true,
            onTap: () {},
            child: const Text('child'),
          ),
        ),
      );

      // Scoped to the DisabledTapDetector subtree to avoid picking up any
      // ExcludeSemantics that the surrounding Scaffold/MaterialApp injects.
      expect(
        find.descendant(
          of: find.byType(DisabledTapDetector),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'disabled: no ExcludeSemantics in DisabledTapDetector subtree',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            DisabledTapDetector(
              enabled: false,
              onTap: () {},
              child: const Text('child'),
            ),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(DisabledTapDetector),
            matching: find.byType(ExcludeSemantics),
          ),
          findsNothing,
        );
      },
    );
  });
}
