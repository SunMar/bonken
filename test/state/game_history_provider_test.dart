import 'dart:convert';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

GameSession session(
  String id,
  DateTime updatedAt, {
  List<String> names = const ['A', 'B', 'C', 'D'],
  List<RoundRecord> rounds = const [],
}) {
  final players = [for (final name in names) Player(name: name)];
  return GameSession(
    id: id,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    players: players,
    firstDealerId: players[0].id,
    rounds: rounds,
  );
}

void main() {
  initializeWidgets();
  setUpPrefs();

  group('build / load', () {
    test('returns empty list when storage is empty', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);
      expect(list, isEmpty);
    });

    testWidgets(
      'enters AsyncError with CorruptStorageException when storage is unreadable',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': 'this is not json',
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const SizedBox()),
        );
        c.read(gameHistoryProvider);
        await tester.pumpAndSettle();
        expect(
          c.read(gameHistoryProvider).error,
          isA<CorruptStorageException>(),
        );
        // Drain the Riverpod retry timer (same pattern as the unsupported test).
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('bonken_game_history');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      },
    );
  });

  group('saveGame', () {
    test('inserts a new session', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('id1', DateTime(2024)));
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
            session('id1', DateTime(2024), names: ['A', 'B', 'C', 'D']),
          );
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(
            session('id1', DateTime(2024, 1, 2), names: ['X', 'Y', 'Z', 'W']),
          );
      final list = c.read(gameHistoryProvider).value!;
      expect(list.length, 1);
      expect(list.first.displayedPlayerNames, ['X', 'Y', 'Z', 'W']);
    });

    test('sorts newest-first by updatedAt', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      await c
          .read(gameHistoryProvider.notifier)
          .saveGame(session('old', DateTime(2024)));
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
          .saveGame(session('persisted', DateTime(2024)));
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final list = await c2.read(gameHistoryProvider.future);
      expect(list.length, 1);
      expect(list.first.id, 'persisted');
    });
  });

  group('unsupported storage version', () {
    // Riverpod 3 schedules a 200ms retry when build() throws. After asserting
    // the error state, we remove the bad prefs key and drain the timer so
    // the retry succeeds (returns []) and no pending timers remain at teardown.
    Future<void> drainRetry(WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('game_history');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'enters AsyncError with UnsupportedStorageVersionException for a future version',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'game_history': '{"version":99,"games":[]}',
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const SizedBox()),
        );
        c.read(gameHistoryProvider);
        await tester.pumpAndSettle();

        expect(
          c.read(gameHistoryProvider).error,
          isA<UnsupportedStorageVersionException>(),
        );

        await drainRetry(tester);
      },
    );

    testWidgets('clearHistory resets state to empty and removes storage key', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'game_history': '{"version":99,"games":[]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SizedBox()),
      );
      c.read(gameHistoryProvider);
      await tester.pumpAndSettle();
      expect(
        c.read(gameHistoryProvider).error,
        isA<UnsupportedStorageVersionException>(),
      );

      await c.read(gameHistoryProvider.notifier).clearHistory();

      expect(c.read(gameHistoryProvider).value, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('game_history'), isFalse);

      // Drain the retry timer (prefs key is gone so build() returns [] cleanly).
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
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
          .saveGame(session('drop', DateTime(2024)));
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
          .saveGame(session('keep', DateTime(2024)));
      await c.read(gameHistoryProvider.notifier).deleteGame('does-not-exist');
      expect(c.read(gameHistoryProvider).value!.length, 1);
    });
  });

  group('storage migrations (v1 → v2 → v3)', () {
    // ---------------------------------------------------------------------------
    // Helpers for constructing v1 JSON
    // ---------------------------------------------------------------------------

    /// Builds a v1 game JSON object (the array element format used by
    /// `bonken_game_history` before the UUID migration).
    Map<String, dynamic> v1Game({
      String id = 'sess1',
      String createdAt = '2024-01-01T00:00:00.000',
      String updatedAt = '2024-01-01T00:00:00.000',
      List<String> playerNames = const ['Alice', 'Bob', 'Carol', 'Dan'],
      List<Map<String, dynamic>> rounds = const [],
      Map<String, dynamic>? pendingRound,
    }) {
      final m = <String, dynamic>{
        'id': id,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'playerNames': playerNames,
        'rounds': rounds,
      };
      if (pendingRound != null) m['pendingRound'] = pendingRound;
      return m;
    }

    /// Encodes a list of v1 game objects as the raw legacy storage string.
    String v1Storage(List<Map<String, dynamic>> games) => jsonEncode(games);

    // -------------------------------------------------------------------------
    // Score migration
    // -------------------------------------------------------------------------

    test(
      'legacy key: scores are migrated from index-keyed to UUID-keyed',
      () async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'duck',
                  'gameName': 'Bukken',
                  'dealerIndex': 0,
                  'chooserIndex': 1,
                  'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                  'input': {
                    'tricks': [4, 3, 5, 1],
                  },
                },
              ],
            ),
          ]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        expect(list.length, 1);
        final session = list.first;
        expect(session.players.map((p) => p.name), [
          'Alice',
          'Bob',
          'Carol',
          'Dan',
        ]);

        final scores = session.rounds[0].scoresByPlayer;
        expect(scores[session.players[0].id], -40);
        expect(scores[session.players[1].id], -30);
        expect(scores[session.players[2].id], -50);
        expect(scores[session.players[3].id], -10);
      },
    );

    // -------------------------------------------------------------------------
    // Input migration — counts game (Duck: v1 tricks list → canonical counts)
    // -------------------------------------------------------------------------

    test(
      'counts game input (v1 tricks list) migrated to the canonical counts map',
      () async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'duck',
                  'gameName': 'Bukken',
                  'dealerIndex': 0,
                  'chooserIndex': 1,
                  'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                  'input': {
                    'tricks': [4, 3, 5, 1],
                  },
                },
              ],
            ),
          ]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        final input = list.first.rounds[0].input;
        final players = list.first.players;
        // After v1→v2→v3 + load, counts games carry a typed CountsInput.
        final counts = (input as CountsInput).counts;
        expect(counts[players[0].id], 4);
        expect(counts[players[1].id], 3);
        expect(counts[players[2].id], 5);
        expect(counts[players[3].id], 1);
      },
    );

    // -------------------------------------------------------------------------
    // Input migration — RecipientInputDescriptor (KingOfHearts: int → UUID)
    // -------------------------------------------------------------------------

    test(
      'RecipientInputDescriptor input (winner int) migrated to UUID',
      () async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'kingOfHearts',
                  'gameName': 'Harten Heer',
                  'dealerIndex': 0,
                  'chooserIndex': 1,
                  'scores': {'0': 0, '1': 0, '2': -100, '3': 0},
                  'input': {'winner': 2},
                },
              ],
            ),
          ]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        final input = list.first.rounds[0].input;
        final players = list.first.players;
        expect((input as RecipientInput).recipients[0], players[2].id);
      },
    );

    test('RecipientInputDescriptor input (null winner) stays null', () async {
      SharedPreferences.setMockInitialValues({
        'bonken_game_history': v1Storage([
          v1Game(
            rounds: [
              {
                'roundNumber': 1,
                'gameId': 'kingOfHearts',
                'gameName': 'Harten Heer',
                'dealerIndex': 0,
                'chooserIndex': 1,
                'scores': {'0': 0, '1': 0, '2': 0, '3': 0},
                'input': {'winner': null},
              },
            ],
          ),
        ]),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);

      expect(
        (list.first.rounds[0].input as RecipientInput).recipients[0],
        isNull,
      );
    });

    // -------------------------------------------------------------------------
    // Input migration — RecipientInputDescriptor (7th/13th: ints → UUIDs)
    // -------------------------------------------------------------------------

    test(
      'RecipientInputDescriptor input (trick7/13 ints) migrated to UUIDs',
      () async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'seventhAndThirteenth',
                  'gameName': '7e / 13e',
                  'dealerIndex': 0,
                  'chooserIndex': 1,
                  'scores': {'0': -50, '1': 0, '2': -50, '3': 0},
                  'input': {'trick7winner': 0, 'trick13winner': 2},
                },
              ],
            ),
          ]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        final ri = list.first.rounds[0].input as RecipientInput;
        final players = list.first.players;
        expect(ri.recipients[0], players[0].id);
        expect(ri.recipients[1], players[2].id);
      },
    );

    // -------------------------------------------------------------------------
    // Doubles migration (pair keys "a,b" int indices → UUIDs; initiator int → UUID)
    // -------------------------------------------------------------------------

    test('doubles pair keys and initiators are migrated to UUIDs', () async {
      SharedPreferences.setMockInitialValues({
        'bonken_game_history': v1Storage([
          v1Game(
            rounds: [
              {
                'roundNumber': 1,
                'gameId': 'duck',
                'gameName': 'Bukken',
                'dealerIndex': 0,
                'chooserIndex': 1,
                'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                'input': {
                  'tricks': [4, 3, 5, 1],
                },
                'doublesJson': {
                  'pairs': {'0,1': 'doubled', '2,3': 'redoubled'},
                  'initiators': {'0,1': 0, '2,3': 3},
                },
              },
            ],
          ),
        ]),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);

      final players = list.first.players;
      final dm = list.first.rounds[0].doubles;
      // pair 0,1 → doubled
      expect(dm.stateFor(players[0].id, players[1].id), DoubleState.doubled);
      expect(dm.initiatorFor(players[0].id, players[1].id), players[0].id);
      // pair 2,3 → redoubled
      expect(dm.stateFor(players[2].id, players[3].id), DoubleState.redoubled);
      expect(dm.initiatorFor(players[2].id, players[3].id), players[3].id);
    });

    // -------------------------------------------------------------------------
    // firstDealerId back-computation
    // -------------------------------------------------------------------------

    test(
      'firstDealerId derived from last completed round when no pending',
      () async {
        // 2 rounds, last dealer = index 1 (Bob):
        // firstDealerIdx = ((1 - 2 + 1) % 4 + 4) % 4 = 0 → Alice
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'duck',
                  'gameName': 'Bukken',
                  'dealerIndex': 0,
                  'chooserIndex': 1,
                  'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                  'input': {
                    'tricks': [4, 3, 5, 1],
                  },
                },
                {
                  'roundNumber': 2,
                  'gameId': 'duck',
                  'gameName': 'Bukken',
                  'dealerIndex': 1,
                  'chooserIndex': 2,
                  'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                  'input': {
                    'tricks': [4, 3, 5, 1],
                  },
                },
              ],
            ),
          ]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        final session = list.first;
        // firstDealer = Alice (index 0)
        expect(session.firstDealerId, session.players[0].id);
      },
    );

    test(
      'firstDealerId derived from pending round dealerIndex when present',
      () async {
        // 1 round completed, pending dealerIndex = 2 (Carol):
        // firstDealerIdx = ((2 - 1) % 4 + 4) % 4 = 1 → Bob
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'duck',
                  'gameName': 'Bukken',
                  'dealerIndex': 1,
                  'chooserIndex': 2,
                  'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                  'input': {
                    'tricks': [4, 3, 5, 1],
                  },
                },
              ],
              pendingRound: {
                'gameId': 'queens',
                'gameName': 'Vrouwen',
                'dealerIndex': 2,
                'chooserIndex': 3,
                'input': <String, dynamic>{},
              },
            ),
          ]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        final session = list.first;
        // firstDealer = Bob (index 1)
        expect(session.firstDealerId, session.players[1].id);
      },
    );

    test(
      'firstDealerId defaults to index 0 when there are no rounds',
      () async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([v1Game()]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        expect(list.first.firstDealerId, list.first.players[0].id);
      },
    );

    // -------------------------------------------------------------------------
    // pending round migration
    // -------------------------------------------------------------------------

    test('pending round chooserId and input are migrated to UUIDs', () async {
      SharedPreferences.setMockInitialValues({
        'bonken_game_history': v1Storage([
          v1Game(
            pendingRound: {
              'gameId': 'kingOfHearts',
              'gameName': 'Harten Heer',
              'dealerIndex': 0,
              'chooserIndex': 3,
              'input': {'winner': 1},
            },
          ),
        ]),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);

      final session = list.first;
      final pending = session.pendingRound!;
      expect(pending.chooserId, session.players[3].id);
      expect(
        (pending.input as RecipientInput).recipients[0],
        session.players[1].id,
      );
    });

    // -------------------------------------------------------------------------
    // Storage key management
    // -------------------------------------------------------------------------

    test(
      'legacy key is removed and current key is written after migration',
      () async {
        SharedPreferences.setMockInitialValues({
          'bonken_game_history': v1Storage([v1Game()]),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await c.read(gameHistoryProvider.future);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('bonken_game_history'), isFalse);
        expect(prefs.containsKey('game_history'), isTrue);

        // Verify what was written is valid versioned (current) JSON.
        final written =
            jsonDecode(prefs.getString('game_history')!)
                as Map<String, dynamic>;
        expect(written['version'], 4);
        expect(written['games'], isA<List<dynamic>>());
      },
    );

    // -------------------------------------------------------------------------
    // Defensive versioned migration (version: 1 in 'game_history' key)
    // -------------------------------------------------------------------------

    test('version:1 in versioned key is migrated to current version', () async {
      SharedPreferences.setMockInitialValues({
        'game_history': jsonEncode({
          'version': 1,
          'games': [
            v1Game(
              rounds: [
                {
                  'roundNumber': 1,
                  'gameId': 'duck',
                  'gameName': 'Bukken',
                  'dealerIndex': 0,
                  'chooserIndex': 1,
                  'scores': {'0': -40, '1': -30, '2': -50, '3': -10},
                  'input': {
                    'tricks': [4, 3, 5, 1],
                  },
                },
              ],
            ),
          ],
        }),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);

      // Full v1→v2→v3 chain ran: sessions loaded correctly.
      expect(list.length, 1);
      final session = list.first;
      expect(session.players.map((p) => p.name), [
        'Alice',
        'Bob',
        'Carol',
        'Dan',
      ]);
      // Input is now a typed CountsInput.
      final counts = (session.rounds[0].input as CountsInput).counts;
      expect(counts[session.players[2].id], 5);

      // Verify storage was upgraded to the current version.
      final prefs = await SharedPreferences.getInstance();
      final written =
          jsonDecode(prefs.getString('game_history')!) as Map<String, dynamic>;
      expect(written['version'], 4);
    });

    test('version:2 in versioned key is migrated to current version', () async {
      // A genuine v2 record: UUID-keyed values under the OLD per-game input
      // keys. The v2→v3 step must reshape it to the uniform counts list.
      final players = [
        for (final n in ['Alice', 'Bob', 'Carol', 'Dan']) Player(name: n),
      ];
      final ids = [for (final p in players) p.id];
      SharedPreferences.setMockInitialValues({
        'game_history': jsonEncode({
          'version': 2,
          'games': [
            {
              'id': 'v2sess',
              'createdAt': '2024-01-01T00:00:00.000',
              'updatedAt': '2024-01-01T00:00:00.000',
              'players': [for (final p in players) p.toJson()],
              'firstDealerId': ids[0],
              'rounds': [
                {
                  'roundNumber': 1,
                  'gameId': 'seventhAndThirteenth',
                  'gameName': '7e / 13e',
                  'chooserId': ids[1],
                  'scores': {ids[0]: -50, ids[1]: 0, ids[2]: -50, ids[3]: 0},
                  'input': {'trick7winner': ids[0], 'trick13winner': ids[2]},
                },
              ],
            },
          ],
        }),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final list = await c.read(gameHistoryProvider.future);

      // Recipients reshaped to positional list, order preserved.
      final ri = list.first.rounds[0].input as RecipientInput;
      expect(ri.recipients[0], ids[0]);
      expect(ri.recipients[1], ids[2]);

      final prefs = await SharedPreferences.getInstance();
      final written =
          jsonDecode(prefs.getString('game_history')!) as Map<String, dynamic>;
      expect(written['version'], 4);
      // On disk the round input is the uniform counts list.
      final game0 =
          (written['games'] as List<dynamic>).first as Map<String, dynamic>;
      final round0 =
          (game0['rounds'] as List<dynamic>).first as Map<String, dynamic>;
      final roundInput = round0['input'] as Map<String, dynamic>;
      expect(roundInput.keys.toList(), ['counts']);
      expect((roundInput['counts'] as List).length, 2);
    });

    test(
      'version:3 doublesJson is reshaped to flat pair-object format',
      () async {
        final players = [
          for (final n in ['Alice', 'Bob', 'Carol', 'Dan']) Player(name: n),
        ];
        final ids = [for (final p in players) p.id];
        // Pair keys must be canonical (lexicographically smaller UUID first),
        // matching what real v3 storage always contained.
        String pairKey(String a, String b) =>
            a.compareTo(b) <= 0 ? '$a,$b' : '$b,$a';
        final k01 = pairKey(ids[0], ids[1]);
        final k23 = pairKey(ids[2], ids[3]);
        SharedPreferences.setMockInitialValues({
          'game_history': jsonEncode({
            'version': 3,
            'games': [
              {
                'id': 'v3sess',
                'createdAt': '2024-01-01T00:00:00.000',
                'updatedAt': '2024-01-01T00:00:00.000',
                'players': [for (final p in players) p.toJson()],
                'firstDealerId': ids[0],
                'rounds': [
                  {
                    'roundNumber': 1,
                    'gameId': 'duck',
                    'gameName': 'Bukken',
                    'chooserId': ids[1],
                    'scores': {
                      ids[0]: -40,
                      ids[1]: -30,
                      ids[2]: -50,
                      ids[3]: -10,
                    },
                    'input': {
                      'counts': [
                        {ids[0]: 4, ids[1]: 3, ids[2]: 5, ids[3]: 1},
                      ],
                    },
                    'doublesJson': {
                      'pairs': {k01: 'doubled', k23: 'redoubled'},
                      'initiators': {k01: ids[0], k23: ids[3]},
                    },
                  },
                ],
              },
            ],
          }),
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final list = await c.read(gameHistoryProvider.future);

        final dm = list.first.rounds[0].doubles;
        expect(dm.stateFor(ids[0], ids[1]), DoubleState.doubled);
        expect(dm.initiatorFor(ids[0], ids[1]), ids[0]);
        expect(dm.stateFor(ids[2], ids[3]), DoubleState.redoubled);
        expect(dm.initiatorFor(ids[2], ids[3]), ids[3]);
      },
    );
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
        session('1', DateTime(2024), names: ['Alice', 'Bob', 'Carol', 'Dan']),
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
        session('1', DateTime(2024), names: ['Alice', 'Alice', 'Bob', 'Bob']),
      );
      final s = n.playerNameSuggestions;
      expect(s.toSet().length, s.length);
    });

    test('breaks frequency ties alphabetically (case-insensitive)', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      final n = c.read(gameHistoryProvider.notifier);
      // All four names appear exactly once → must be alphabetical.
      // Names are inserted in non-alphabetical insertion order to make
      // sure the sort, not insertion order, drives the result.
      await n.saveGame(
        session('1', DateTime(2024), names: ['carol', 'Alice', 'bob', 'Dan']),
      );
      expect(n.playerNameSuggestions, ['Alice', 'bob', 'carol', 'Dan']);
    });
  });
}
