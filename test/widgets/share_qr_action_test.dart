import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/qr_display_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/platform_io_providers.dart';
import 'package:bonken/widgets/share_qr_action.dart';
import 'package:bonken/widgets/share_result_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  setUpPrefs();

  final players = [
    Player(name: 'Alice'),
    Player(name: 'Bob'),
    Player(name: 'Carol'),
    Player(name: 'Dan'),
  ];

  RoundRecord dominoesRound(int n) => RoundRecord(
    roundNumber: n,
    game: const Dominoes(),
    chooserId: players[1].id,
    scoresByPlayer: {for (final p in players) p.id: p == players[1] ? -100 : 0},
    input: RecipientInput([players[1].id]),
    doubles: const DoubleMatrix(),
  );

  GameSession game({required bool finished}) => GameSession(
    id: kGameId1,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: players,
    firstDealerId: players.first.id,
    rounds: [
      for (var n = 1; n <= (finished ? GameSession.totalRounds : 1); n++)
        dominoesRound(n),
    ],
  );

  Future<void> pumpGame(WidgetTester tester, {required bool finished}) async {
    final container = ProviderContainer(
      overrides: [
        screenBrightnessProvider.overrideWithValue(FakeScreenBrightness()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gameHistoryProvider.future);
    final session = game(finished: finished);
    await container.read(gameHistoryProvider.notifier).saveGame(session);
    container.read(calculatorProvider.notifier).loadSession(session);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500)); // drain autosave
    await tester.pumpAndSettle();
  }

  testWidgets(
    'for an in-progress game the Share action is present but disabled',
    (tester) async {
      await pumpGame(tester, finished: false);
      expect(find.byType(ShareQrAction), findsOneWidget);
      // Always present now, just disabled (native M3 disabled colours).
      expect(find.byType(ShareResultAction), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(ShareResultAction),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('tapping the disabled Share action explains why', (tester) async {
    await pumpGame(tester, finished: false);
    // The transparent overlay is the hit target for a Mechanism-A disabled
    // button, so tap the ShareResultAction, not the disabled icon beneath it.
    await tester.tap(find.byType(ShareResultAction));
    await tester.pump();
    expect(find.text(kShareUnfinishedMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // drain the snackbar timer
    await tester.pumpAndSettle();
  });

  testWidgets(
    'on a finished game the QR action sits left of an enabled Share',
    (tester) async {
      await pumpGame(tester, finished: true);
      expect(find.byType(ShareQrAction), findsOneWidget);
      expect(find.byType(ShareResultAction), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(ShareResultAction),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      final qrX = tester.getTopLeft(find.byType(ShareQrAction)).dx;
      final shareX = tester.getTopLeft(find.byType(ShareResultAction)).dx;
      expect(qrX, lessThan(shareX));
    },
  );

  testWidgets('tapping the QR action opens the share screen', (tester) async {
    await pumpGame(tester, finished: false);
    await tester.tap(find.byType(ShareQrAction));
    await tester.pumpAndSettle();
    expect(find.byType(QrDisplayScreen), findsOneWidget);
  });
}
