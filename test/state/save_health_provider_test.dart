import 'package:bonken/models/game_session.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/save_health_provider.dart';
import 'package:bonken/state/settings_provider.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/storage_exceptions.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  initializeWidgets();

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('SaveHealthNotifier', () {
    test('starts healthy', () {
      expect(makeContainer().read(saveHealthyProvider), isTrue);
    });

    test('markFailed → unhealthy; markOk → healthy', () {
      final container = makeContainer();
      final notifier = container.read(saveHealthyProvider.notifier);

      notifier.markFailed();
      expect(container.read(saveHealthyProvider), isFalse);

      notifier.markOk();
      expect(container.read(saveHealthyProvider), isTrue);
    });
  });

  group('game-history writes', () {
    test('an incidental write swallows a fault and flags the banner', () async {
      setAsyncPrefsWithFailingWrites();
      final container = makeContainer();
      await container.read(gameHistoryProvider.future);

      // deleteGame's _persist write fails; it must NOT throw (banner is the
      // signal), but it flips the health flag.
      await container.read(gameHistoryProvider.notifier).deleteGame('absent');

      expect(container.read(saveHealthyProvider), isFalse);
    });

    test(
      'replaceAll (import) surfaces the fault as PersistenceWriteException',
      () async {
        setAsyncPrefsWithFailingWrites();
        final container = makeContainer();
        await container.read(gameHistoryProvider.future);

        await expectLater(
          container
              .read(gameHistoryProvider.notifier)
              .replaceAll(const <GameSession>[]),
          throwsA(isA<PersistenceWriteException>()),
        );
        expect(container.read(saveHealthyProvider), isFalse);
      },
    );

    test('a later successful write clears the banner', () async {
      setAsyncPrefs();
      final container = makeContainer();
      container.read(saveHealthyProvider.notifier).markFailed();
      await container.read(gameHistoryProvider.future);

      await container.read(gameHistoryProvider.notifier).deleteGame('absent');

      expect(container.read(saveHealthyProvider), isTrue);
    });
  });

  group('settings writes', () {
    test(
      'a setting change applies in memory and flags the banner on a fault',
      () async {
        setAsyncPrefsWithFailingWrites();
        final container = makeContainer();

        // Must NOT throw, and the change still takes effect in memory.
        await container
            .read(settingsProvider.notifier)
            .setThemeMode(ThemeMode.dark);

        expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
        expect(container.read(saveHealthyProvider), isFalse);
      },
    );

    test('replaceAll (import) surfaces the fault', () async {
      setAsyncPrefsWithFailingWrites();
      final container = makeContainer();

      await expectLater(
        container
            .read(settingsProvider.notifier)
            .replaceAll(const PersistedSettings.defaults()),
        throwsA(isA<PersistenceWriteException>()),
      );
      expect(container.read(saveHealthyProvider), isFalse);
    });
  });

  group('retryPersist', () {
    test('a recovered disk clears the banner', () async {
      setAsyncPrefs(); // disk works again
      final container = makeContainer();
      container.read(saveHealthyProvider.notifier).markFailed();
      await container.read(gameHistoryProvider.future);

      await container.read(gameHistoryProvider.notifier).retryPersist();
      expect(container.read(saveHealthyProvider), isTrue);

      // Settings retry behaves the same.
      container.read(saveHealthyProvider.notifier).markFailed();
      await container.read(settingsProvider.notifier).retryPersist();
      expect(container.read(saveHealthyProvider), isTrue);
    });

    test('a still-failing write keeps the banner', () async {
      setAsyncPrefsWithFailingWrites();
      final container = makeContainer();
      container.read(saveHealthyProvider.notifier).markFailed();
      await container.read(gameHistoryProvider.future);

      await container.read(gameHistoryProvider.notifier).retryPersist();
      expect(container.read(saveHealthyProvider), isFalse);
    });
  });
}
