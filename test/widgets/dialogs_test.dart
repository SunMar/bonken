import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/widgets/dialogs.dart';

Future<void> pumpHost(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

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
                title: 'Verwijderen?',
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
      expect(find.text('Verwijderen?'), findsOneWidget);
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

    testWidgets('destructive uses error color on confirm button', (
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
      expect(find.text('Verwijderen'), findsOneWidget);
    });

    testWidgets('asserts when neither contentText nor content is provided', (
      tester,
    ) async {
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
      expect(tester.takeException(), isA<AssertionError>());
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
}
