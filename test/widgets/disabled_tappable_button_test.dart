import 'package:bonken/widgets/disabled_tappable_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('DisabledTappableButton', () {
    testWidgets(
      'enabled: builder gets the action, no overlay, tap fires onPressed',
      (tester) async {
        var pressed = 0;
        var disabledTaps = 0;
        VoidCallback? received;
        await tester.pumpWidget(
          wrap(
            DisabledTappableButton(
              onPressed: () => pressed++,
              onDisabledTap: () => disabledTaps++,
              builder: (onPressed) {
                received = onPressed;
                return FilledButton(
                  onPressed: onPressed,
                  child: const Text('Opslaan'),
                );
              },
            ),
          ),
        );

        // The single nullable onPressed is threaded through to the button.
        expect(received, isNotNull);
        // No overlay is mounted while the action is live.
        expect(
          find.descendant(
            of: find.byType(DisabledTappableButton),
            matching: find.byType(ExcludeSemantics),
          ),
          findsNothing,
        );

        await tester.tap(find.text('Opslaan'));
        expect(pressed, 1);
        expect(disabledTaps, 0);
      },
    );

    testWidgets(
      'disabled with onDisabledTap: button truly disabled, overlay fires why',
      (tester) async {
        var disabledTaps = 0;
        VoidCallback? received;
        await tester.pumpWidget(
          wrap(
            DisabledTappableButton(
              onPressed: null,
              onDisabledTap: () => disabledTaps++,
              builder: (onPressed) {
                received = onPressed;
                return FilledButton(
                  onPressed: onPressed,
                  child: const Text('Opslaan'),
                );
              },
            ),
          ),
        );

        // Builder got null → the button is genuinely disabled.
        expect(received, isNull);
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
        // Overlay is mounted (ExcludeSemantics so AT sees the disabled button).
        expect(
          find.descendant(
            of: find.byType(DisabledTappableButton),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );

        // The overlay intercepts the tap before the disabled button.
        await tester.tap(find.text('Opslaan'), warnIfMissed: false);
        expect(disabledTaps, 1);
      },
    );

    testWidgets('disabled without onDisabledTap: no overlay mounted', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          DisabledTappableButton(
            onPressed: null,
            onDisabledTap: null,
            builder: (onPressed) => FilledButton(
              onPressed: onPressed,
              child: const Text('Opslaan'),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(DisabledTappableButton),
          matching: find.byType(ExcludeSemantics),
        ),
        findsNothing,
      );
    });
  });
}
