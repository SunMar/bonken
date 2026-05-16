// Tests for [showDealerPickerDialog]: covers the three resolve paths
// ([NextDealerNext], [NextDealerRandom], [NextDealerSpecific]) and the
// `null` result for cancel/dismiss.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/widgets/dealer_picker_dialog.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

/// Pumps a host with an "open" button that, when tapped, invokes
/// [showDealerPickerDialog] and appends the returned future to [out].
///
/// The future is *not* awaited by the helper so tests can interact with
/// the dialog before resolving it. Wrapping in a list also sidesteps
/// Dart's auto-flattening of `Future<Future<X>>`.
Future<void> _open(
  WidgetTester tester, {
  int previousDealerIndex = 0,
  required List<Future<NextDealerChoice?>> out,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () {
              out.add(
                showDealerPickerDialog(
                  ctx,
                  playerNames: _names,
                  previousDealerIndex: previousDealerIndex,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows next dealer name as the "Volgende speler" subtitle', (
    tester,
  ) async {
    final out = <Future<NextDealerChoice?>>[];
    await _open(tester, previousDealerIndex: 1, out: out); // next = Carol
    expect(find.text('Volgende speler'), findsOneWidget);
    expect(find.text('Carol'), findsWidgets);
  });

  testWidgets('tapping "Volgende speler" resolves to NextDealerNext', (
    tester,
  ) async {
    final out = <Future<NextDealerChoice?>>[];
    await _open(tester, out: out);
    await tester.tap(find.text('Volgende speler'));
    await tester.pumpAndSettle();
    expect(await out.single, isA<NextDealerNext>());
  });

  testWidgets('tapping "Willekeurig" resolves to NextDealerRandom', (
    tester,
  ) async {
    final out = <Future<NextDealerChoice?>>[];
    await _open(tester, out: out);
    await tester.tap(find.text('Willekeurig'));
    await tester.pumpAndSettle();
    expect(await out.single, isA<NextDealerRandom>());
  });

  testWidgets(
    'tapping a player name resolves to NextDealerSpecific with their index',
    (tester) async {
      final out = <Future<NextDealerChoice?>>[];
      await _open(tester, out: out);
      // The specific-player tiles live below the divider. Tapping the
      // bare name (which has no subtitle) targets the specific tile
      // rather than the "Volgende speler" subtitle.
      await tester.tap(find.text('Dan'));
      await tester.pumpAndSettle();
      final choice = await out.single;
      expect(choice, isA<NextDealerSpecific>());
      expect((choice as NextDealerSpecific).index, 3);
    },
  );

  testWidgets('tapping "Annuleren" resolves to null', (tester) async {
    final out = <Future<NextDealerChoice?>>[];
    await _open(tester, out: out);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(await out.single, isNull);
  });
}
