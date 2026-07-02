import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/screens/qr_display_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/platform_io_providers.dart';
import 'package:bonken/widgets/qr_code_view.dart';
import 'package:bonken/widgets/scoreboard_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  setUpPrefs();

  final four = [
    Player(name: 'A'),
    Player(name: 'B'),
    Player(name: 'C'),
    Player(name: 'D'),
  ];

  GameSession session({String? gameName}) => GameSession(
    id: kGameId1,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: four,
    firstDealerId: four.first.id,
    rounds: const [],
    gameName: gameName,
  );

  Future<(ProviderContainer, FakeScreenBrightness)> pumpScreen(
    WidgetTester tester, {
    String? gameName,
  }) async {
    final fake = FakeScreenBrightness();
    final container = ProviderContainer(
      overrides: [screenBrightnessProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(gameHistoryProvider.future);
    final s = session(gameName: gameName);
    await container.read(gameHistoryProvider.notifier).saveGame(s);
    container.read(calculatorProvider.notifier).loadSession(s);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: QrDisplayScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500)); // drain autosave
    await tester.pumpAndSettle();
    return (container, fake);
  }

  testWidgets('shows the QR and a scorecard', (tester) async {
    await pumpScreen(tester, gameName: 'Vrijdag');
    expect(find.byType(QrCodeView), findsOneWidget);
    expect(find.byType(ScoreboardCard), findsOneWidget);
  });

  testWidgets('raises brightness on show and restores on leave', (
    tester,
  ) async {
    final (_, fake) = await pumpScreen(tester);
    expect(fake.setMaxCount, greaterThanOrEqualTo(1));
    expect(fake.resetCount, 0);

    // Leaving the screen restores brightness.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(fake.resetCount, greaterThanOrEqualTo(1));
  });

  testWidgets('restores brightness when backgrounded, re-raises on resume', (
    tester,
  ) async {
    final (_, fake) = await pumpScreen(tester);
    final resetBefore = fake.resetCount;
    final setMaxBefore = fake.setMaxCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fake.resetCount, greaterThan(resetBefore));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fake.setMaxCount, greaterThan(setMaxBefore));
  });

  testWidgets('unnamed game shows the naming prompt', (tester) async {
    await pumpScreen(tester);
    expect(find.text(kGameNamePrompt), findsOneWidget);
  });

  testWidgets(
    'editing the name dims while the dialog is open, persists it, and '
    'restores brightness',
    (tester) async {
      final (container, fake) = await pumpScreen(tester);
      final setMaxBefore = fake.setMaxCount;

      await tester.tap(find.text(kGameNamePrompt));
      await tester.pumpAndSettle();
      // Dialog open → dimmed.
      expect(fake.resetCount, greaterThanOrEqualTo(1));

      await tester.enterText(find.byType(TextField), 'Vrijdagavond');
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      // Name persisted to the session…
      expect(
        container.read(calculatorProvider.notifier).buildSession()!.gameName,
        'Vrijdagavond',
      );
      // …shown on the screen (button label + scorecard title)…
      expect(find.text('Vrijdagavond'), findsWidgets);
      expect(find.text(kGameNamePrompt), findsNothing);
      // …and brightness brought back up after the dialog closed.
      expect(fake.setMaxCount, greaterThan(setMaxBefore));

      await tester.pump(const Duration(milliseconds: 500)); // drain autosave
    },
  );
}
