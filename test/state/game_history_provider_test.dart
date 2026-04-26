import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bonken/models/game_session.dart';
import 'package:bonken/state/game_history_provider.dart';

GameSession session(
  String id,
  DateTime updatedAt, {
  List<String> names = const ['A', 'B', 'C', 'D'],
  List<RoundSummary> rounds = const [],
}) => GameSession(
  id: id,
  createdAt: updatedAt,
  updatedAt: updatedAt,
  playerNames: names,
  rounds: rounds,
);

void main() {
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('build / load', () {
    test('returns empty list when storage is empty', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);
      expect(list, isEmpty);
    });

    test('returns empty list when storage is corrupt', () async {
      SharedPreferences.setMockInitialValues({
        'bonken_game_history': 'this is not json',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);
      expect(list, isEmpty);
    });
  });

  group('saveGame', () {
    test('inserts a new session', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('id1', DateTime(2024, 1, 1)));
      final list = c.read(gameHistoryProvider).value!;
      expect(list.length, 1);
      expect(list.first.id, 'id1');
    });

    test('updates a session in place when id matches', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(
            session('id1', DateTime(2024, 1, 1), names: ['A', 'B', 'C', 'D']),
          );
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(
            session('id1', DateTime(2024, 1, 2), names: ['X', 'Y', 'Z', 'W']),
          );
      final list = c.read(gameHistoryProvider).value!;
      expect(list.length, 1);
      expect(list.first.playerNames, ['X', 'Y', 'Z', 'W']);
    });

    test('sorts newest-first by updatedAt', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('old', DateTime(2024, 1, 1)));
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('new', DateTime(2024, 1, 5)));
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('mid', DateTime(2024, 1, 3)));
      final ids = c.read(gameHistoryProvider).value!.map((s) => s.id).toList();
      expect(ids, ['new', 'mid', 'old']);
    });

    test('persists across container rebuilds', () async {
      final c1 = ProviderContainer();
      await c1.read(gameHistoryProvider.future);
      await c1
          .read(gameHistoryProvider.notifier)
          .saveGame(session('persisted', DateTime(2024, 1, 1)));
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final list = await c2.read(gameHistoryProvider.future);
      expect(list.length, 1);
      expect(list.first.id, 'persisted');
    });
  });

  group('deleteGame', () {
    test('removes the session by id', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('keep', DateTime(2024, 1, 2)));
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('drop', DateTime(2024, 1, 1)));
      await c.read(gameHistoryProvider.notifier).deleteGame('drop');
      final list = c.read(gameHistoryProvider).value!;
      expect(list.length, 1);
      expect(list.first.id, 'keep');
    });

    test('is a no-op when id is unknown', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('keep', DateTime(2024, 1, 1)));
      await c.read(gameHistoryProvider.notifier).deleteGame('does-not-exist');
      expect(c.read(gameHistoryProvider).value!.length, 1);
    });
  });

  group('playerNameSuggestions', () {
    test('returns empty list before history is loaded', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(gameHistoryProvider.notifier).playerNameSuggestions,
        isEmpty,
      );
    });

    test('ranks names by frequency, descending', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      final n = c.read(gameHistoryProvider.notifier);
      await n.saveGame(
        session(
          '1',
          DateTime(2024, 1, 1),
          names: ['Alice', 'Bob', 'Carol', 'Dan'],
        ),
      );
      await n.saveGame(
        session(
          '2',
          DateTime(2024, 1, 2),
          names: ['Alice', 'Bob', 'Eve', 'Frank'],
        ),
      );
      await n.saveGame(
        session(
          '3',
          DateTime(2024, 1, 3),
          names: ['Alice', 'Gina', 'Hank', 'Iris'],
        ),
      );
      final suggestions = n.playerNameSuggestions;
      // Alice appears 3x → first.  Bob 2x → second.  Others 1x.
      expect(suggestions.first, 'Alice');
      expect(suggestions[1], 'Bob');
    });

    test('deduplicates names', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      final n = c.read(gameHistoryProvider.notifier);
      await n.saveGame(
        session(
          '1',
          DateTime(2024, 1, 1),
          names: ['Alice', 'Alice', 'Bob', 'Bob'],
        ),
      );
      final s = n.playerNameSuggestions;
      expect(s.toSet().length, s.length);
    });
  });
}
