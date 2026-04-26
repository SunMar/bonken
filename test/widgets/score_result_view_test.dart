import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/score_result.dart';
import 'package:bonken/widgets/score_result_view.dart';

const playerNames = ['Alice', 'Bob', 'Carol', 'Dan'];

Future<void> pumpHost(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('ScoreResultView', () {
    testWidgets('shows formatted scores with correct sign', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(scores: {0: 80, 1: 80, 2: 40, 3: 60}),
          game: const Clubs(),
          playerNames: playerNames,
        ),
      );
      expect(find.text('+80'), findsNWidgets(2));
      expect(find.text('+40'), findsOneWidget);
      expect(find.text('+60'), findsOneWidget);
    });

    testWidgets('marks the highest scorer with the trophy icon', (
      tester,
    ) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(scores: {0: 100, 1: 50, 2: 80, 3: 30}),
          game: const Clubs(),
          playerNames: playerNames,
        ),
      );
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('marks all tied winners with trophy icons', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(scores: {0: 100, 1: 100, 2: 50, 3: 10}),
          game: const Clubs(),
          playerNames: playerNames,
        ),
      );
      expect(find.byIcon(Icons.emoji_events), findsNWidgets(2));
    });

    testWidgets('does NOT mark a winner when isPartial', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(scores: {0: 100, 1: 50, 2: 80, 3: 30}),
          game: const Clubs(),
          playerNames: playerNames,
          isPartial: true,
        ),
      );
      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });

    testWidgets('hides Score header when showHeader is false', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(scores: {0: 0, 1: 0, 2: 0, 3: 0}),
          game: const Clubs(),
          playerNames: playerNames,
          showHeader: false,
        ),
      );
      expect(find.text('Score'), findsNothing);
    });
  });
}
