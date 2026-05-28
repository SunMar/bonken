import 'dart:async';

import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/widgets/game_deleted_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

GameSession _session(String id) {
  final players = [
    Player(name: 'Alice'),
    Player(name: 'Bob'),
    Player(name: 'Carol'),
    Player(name: 'Dan'),
  ];
  return GameSession(
    id: id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    players: players,
    firstDealerId: players[0].id,
    rounds: const [],
  );
}

void main() {
  initializeWidgets();
  setUpPrefs();

  group('showGameDeletedSnackBar', () {
    testWidgets('shows "Spel verwijderd" with an "Ongedaan maken" action', (
      tester,
    ) async {
      late ScaffoldMessengerState messenger;
      late ProviderContainer container;
      final session = _session('s1');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  messenger = ScaffoldMessenger.of(ctx);
                  container = ProviderScope.containerOf(ctx, listen: false);
                  return ElevatedButton(
                    onPressed: () =>
                        showGameDeletedSnackBar(messenger, container, session),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await container.read(gameHistoryProvider.future);

      await tester.tap(find.text('open'));
      await tester.pump();

      expect(find.text('Spel verwijderd'), findsOneWidget);
      expect(find.text('Ongedaan maken'), findsOneWidget);

      // Drain the helper's belt-and-suspenders 5s Timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping "Ongedaan maken" re-saves the deleted session', (
      tester,
    ) async {
      late ScaffoldMessengerState messenger;
      late ProviderContainer container;
      final session = _session('s1');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  messenger = ScaffoldMessenger.of(ctx);
                  container = ProviderScope.containerOf(ctx, listen: false);
                  return ElevatedButton(
                    onPressed: () =>
                        showGameDeletedSnackBar(messenger, container, session),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Pre-condition: history is empty (session was just "deleted").
      final history = await container.read(gameHistoryProvider.future);
      expect(history, isEmpty);

      await tester.tap(find.text('open'));
      await tester.pump();
      // Let the snackbar slide-in animation finish so the action button
      // is hit-testable.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Ongedaan maken'));
      await tester.pump();

      // Undo re-saves through the root container.
      final restored = container.read(gameHistoryProvider).value;
      expect(restored, hasLength(1));
      expect(restored!.single.id, 's1');

      // Drain the helper's belt-and-suspenders 5s Timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('survives the originating widget being disposed', (
      tester,
    ) async {
      // Reproduces the bug that motivated the ProviderContainer parameter:
      // before the fix, the snackbar captured a WidgetRef from a screen
      // that got disposed by pushAndRemoveUntil, and the undo callback
      // silently no-op'd.
      late ScaffoldMessengerState messenger;
      late ProviderContainer container;
      final session = _session('s1');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (rootCtx) {
                messenger = ScaffoldMessenger.of(rootCtx);
                container = ProviderScope.containerOf(rootCtx, listen: false);
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      // Show the snackbar, then immediately replace the
                      // route so the originating widget tree is gone
                      // before "Ongedaan maken" is tapped.
                      showGameDeletedSnackBar(messenger, container, session);
                      unawaited(
                        Navigator.of(rootCtx).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const Scaffold(body: Text('next screen')),
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await container.read(gameHistoryProvider.future);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('next screen'), findsOneWidget);
      expect(find.text('Ongedaan maken'), findsOneWidget);

      await tester.tap(find.text('Ongedaan maken'));
      await tester.pump();

      final restored = container.read(gameHistoryProvider).value;
      expect(restored, hasLength(1));
      expect(restored!.single.id, 's1');

      // Drain the helper's belt-and-suspenders 5s Timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('replaces a previously visible snackbar', (tester) async {
      late ScaffoldMessengerState messenger;
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  messenger = ScaffoldMessenger.of(ctx);
                  container = ProviderScope.containerOf(ctx, listen: false);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      messenger.showSnackBar(const SnackBar(content: Text('older')));
      await tester.pump();
      expect(find.text('older'), findsOneWidget);

      showGameDeletedSnackBar(messenger, container, _session('s1'));
      await tester.pump();

      expect(find.text('older'), findsNothing);
      expect(find.text('Spel verwijderd'), findsOneWidget);

      // Drain the helper's belt-and-suspenders 5s Timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
