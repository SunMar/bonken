import 'package:bonken/models/player.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/save_health_provider.dart';
import 'package:bonken/widgets/persistence_lifecycle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// Drives a full, valid background→foreground cycle (the AppLifecycle listener
/// asserts on invalid transitions), ending on `resumed`.
Future<void> _resume(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

/// Drives the foreground→background edge up to `hidden` (where `onHide` fires).
Future<void> _hide(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  initializeWidgets();

  group('onResume retry', () {
    testWidgets('a recovered disk clears the banner', (tester) async {
      setAsyncPrefsWithFailingWrites();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(saveHealthyProvider.notifier).markFailed();
      await container.read(gameHistoryProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PersistenceLifecycleSync(child: SizedBox.shrink()),
        ),
      );
      expect(container.read(saveHealthyProvider), isFalse);

      setAsyncPrefs(); // user freed space while away
      await _resume(tester);

      expect(container.read(saveHealthyProvider), isTrue);
    });

    testWidgets('resuming while healthy does not write', (tester) async {
      setAsyncPrefsWithFailingWrites();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PersistenceLifecycleSync(child: SizedBox.shrink()),
        ),
      );

      await _resume(tester);

      expect(container.read(saveHealthyProvider), isTrue);
    });
  });

  group('onHide flush', () {
    testWidgets('backgrounding flushes a pending debounced autosave', (
      tester,
    ) async {
      setAsyncPrefs();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Keep the autoDispose calculator alive so it isn't disposed (which would
      // itself flush) before we background.
      container.listen(calculatorProvider, (_, _) {});
      await container.read(gameHistoryProvider.future);

      // Arms the 400ms debounce; the game is not on disk yet.
      container
          .read(calculatorProvider.notifier)
          .startNewGame(
            players: [
              for (final n in ['Piet', 'Marie', 'Kees', 'Ans']) Player(name: n),
            ],
            dealerIndex: 0,
          );
      expect(container.read(gameHistoryProvider).value, isEmpty);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PersistenceLifecycleSync(child: SizedBox.shrink()),
        ),
      );

      await _hide(tester);

      // Flushed immediately on background — without waiting out the debounce.
      expect(container.read(gameHistoryProvider).value, hasLength(1));
    });
  });
}
