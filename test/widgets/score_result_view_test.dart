import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/score_result.dart';
import 'package:bonken/widgets/score_result_view.dart';

import '_helpers.dart';

void main() {
  group('ScoreResultView', () {
    testWidgets('shows formatted scores with correct sign', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(
            scores: {'alice': 80, 'bob': 80, 'carol': 40, 'dan': 60},
          ),
          game: const Clubs(),
          players: players,
          chooserIndex: 0,
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
          result: const ScoreResult(
            scores: {'alice': 100, 'bob': 50, 'carol': 80, 'dan': 30},
          ),
          game: const Clubs(),
          players: players,
          chooserIndex: 0,
        ),
      );
      expect(find.byIcon(Symbols.emoji_events), findsOneWidget);
    });

    testWidgets('marks all tied winners with trophy icons', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(
            scores: {'alice': 100, 'bob': 100, 'carol': 50, 'dan': 10},
          ),
          game: const Clubs(),
          players: players,
          chooserIndex: 0,
        ),
      );
      expect(find.byIcon(Symbols.emoji_events), findsNWidgets(2));
    });

    testWidgets('does NOT mark a winner when isPartial', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(
            scores: {'alice': 100, 'bob': 50, 'carol': 80, 'dan': 30},
          ),
          game: const Clubs(),
          players: players,
          chooserIndex: 0,
          isPartial: true,
        ),
      );
      expect(find.byIcon(Symbols.emoji_events), findsNothing);
    });

    testWidgets('hides Score header when showHeader is false', (tester) async {
      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(
            scores: {'alice': 0, 'bob': 0, 'carol': 0, 'dan': 0},
          ),
          game: const Clubs(),
          players: players,
          chooserIndex: 0,
          showHeader: false,
        ),
      );
      expect(find.text('Score'), findsNothing);
    });

    testWidgets('shows doubles and redoubles chips when present', (
      tester,
    ) async {
      final doubles = DoubleMatrix.empty()
          .withPair(
            playerIds[0],
            playerIds[1],
            DoubleState.doubled,
            initiator: playerIds[0],
          )
          .withPair(
            playerIds[2],
            playerIds[3],
            DoubleState.redoubled,
            initiator: playerIds[3],
          );

      await pumpHost(
        tester,
        ScoreResultView(
          result: const ScoreResult(
            scores: {'alice': 0, 'bob': 0, 'carol': 0, 'dan': 0},
          ),
          game: const Clubs(),
          players: players,
          chooserIndex: 0,
          doubles: doubles,
        ),
      );

      expect(find.text('Alice × Bob'), findsOneWidget);
      expect(find.text('Dan ×× Carol'), findsOneWidget);
    });
  });
}
