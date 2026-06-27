import 'package:bonken/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  group('showConfirmDialog', () {
    testWidgets('returns true when confirm pressed', (tester) async {
      bool? result;
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showConfirmDialog(
                ctx,
                title: 'Verwijderen',
                contentText: 'Weet je het zeker?',
                confirmLabel: 'Ja',
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Verwijderen'), findsOneWidget);

      // Default (non-destructive) confirm is NOT error-tinted (no style override).
      final errorColor = Theme.of(
        tester.element(find.text('Ja')),
      ).colorScheme.error;
      final confirm = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Ja'),
      );
      expect(
        confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
        isNot(errorColor),
      );

      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('returns false when cancel pressed', (tester) async {
      bool? result;
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showConfirmDialog(
                ctx,
                title: 'X',
                contentText: 'Y',
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('returns null when dismissed by tapping the barrier', (
      tester,
    ) async {
      bool? result;
      var resolved = false;
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showConfirmDialog(
                ctx,
                title: 'X',
                contentText: 'Y',
              );
              resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);

      // Tapping the modal barrier (outside the centered dialog) dismisses it
      // without choosing — the future must resolve to null, not true/false.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(resolved, isTrue);
      expect(result, isNull);
    });

    testWidgets('destructive tints the confirm button with the error color', (
      tester,
    ) async {
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showConfirmDialog(
              ctx,
              title: 'X',
              contentText: 'Y',
              destructive: true,
              confirmLabel: 'Verwijderen',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final errorColor = Theme.of(
        tester.element(find.text('Verwijderen')),
      ).colorScheme.error;
      // The confirm button's resolved foreground is the error colour …
      final confirm = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Verwijderen'),
      );
      expect(
        confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
        errorColor,
      );
      // … while the cancel button is never error-tinted.
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Annuleren'),
      );
      expect(
        cancel.style?.foregroundColor?.resolve(<WidgetState>{}),
        isNot(errorColor),
      );
    });

    testWidgets('throws when neither contentText nor content is provided', (
      tester,
    ) async {
      // No defensive `assert` guards the "exactly one of content/contentText"
      // precondition; misuse surfaces loudly when the dialog builds, via the
      // `contentText!` null-check, rather than rendering an empty dialog.
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showConfirmDialog(ctx, title: 'X'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(tester.takeException(), isA<TypeError>());
    });
  });

  group('showInfoDialog', () {
    testWidgets('shows the title and content, dismisses on OK', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showInfoDialog(
              ctx,
              title: 'Klaar',
              contentText: 'Het spel is afgelopen',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Klaar'), findsOneWidget);
      expect(find.text('Het spel is afgelopen'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Klaar'), findsNothing);
    });
  });

  group('showDealerAnnouncementDialog', () {
    testWidgets('shows dealer name and default "random" sentence', (
      tester,
    ) async {
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () =>
                showDealerAnnouncementDialog(ctx, dealerName: 'Carol'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('is geloot als deler.'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('uses "next" sentence when kind is next', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showDealerAnnouncementDialog(
              ctx,
              dealerName: 'Bob',
              kind: DealerAnnouncementKind.next,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('is de volgende deler.'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });
}
