import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_mechanics.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/rule_variants.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../models/_double_matrix_helpers.dart';
import '../test_helpers.dart';

List<Player> _makePlayers(List<String> names) => [
  for (final name in names) Player(name: name),
];

Map<String, int> _t(List<Player> ps, List<int> counts) => {
  for (int i = 0; i < ps.length; i++) ps[i].id: counts[i],
};

ProviderContainer makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpPrefs();
  initializeWidgets();

  group('Initial state', () {
    test('build returns empty state', () {
      final c = makeContainer();
      final s = c.read(calculatorProvider);
      expect(s.sessionId, '');
      expect(s.roundNumber, 1);
      expect(s.history, isEmpty);
      expect(s.selectedGame, isNull);
      expect(s.hasPendingGame, isFalse);
    });
  });

  group('setPlayerName / setDealer / setChooser', () {
    test('setPlayerName updates only the given index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'Alice');
      n.setPlayerName(2, 'Carol');
      expect(c.read(calculatorProvider).playerNames, [
        'Alice',
        '',
        'Carol',
        '',
      ]);
    });

    test('setDealer updates dealer index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(2);
      final s = c.read(calculatorProvider);
      expect(s.dealerIndex, 2);
      expect(s.roundNumber, 1);
      expect(s.history, isEmpty);
    });

    test('setChooser updates the chooser index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setChooser(3);
      expect(c.read(calculatorProvider).chooserIndex, 3);
    });
  });

  group('selectGame', () {
    test('selecting a counts game pre-fills with zeros', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs());
      final s = c.read(calculatorProvider);
      expect(s.selectedGame!.id, 'clubs');
      expect(
        (s.input! as CountsInput).counts.values.every((v) => v == 0),
        isTrue,
      );
      expect(s.doubles.hasAnyDouble, isFalse);
      expect(s.result, isNull);
    });

    test('selecting recipient game leaves slot null', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const KingOfHearts());
      expect((c.read(calculatorProvider).input! as RecipientInput).recipients, [
        null,
      ]);
    });

    test('selecting two-slot recipient game leaves both slots null', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const SeventhAndThirteenth());
      expect((c.read(calculatorProvider).input! as RecipientInput).recipients, [
        null,
        null,
      ]);
    });

    test('chooser defaults to player left of dealer', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(2);
      n.selectGame(const Clubs());
      expect(c.read(calculatorProvider).chooserIndex, 3);
    });
  });

  group('updateInput / recalculate', () {
    test('partial counts produce a partialResult, not a final result', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 3, 2, 0]))); // sum 9 < 13
      final s = c.read(calculatorProvider);
      expect(s.result, isNull);
      expect(s.partialResult, isNotNull);
      expect(s.inputState, InputState.partial);
    });

    test('complete counts produce a final result', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3]))); // sum 13
      final s = c.read(calculatorProvider);
      expect(s.inputState, InputState.complete);
      expect(s.result, isNotNull);
      expect(s.partialResult, isNull);
      expect(s.result!.scores, _t(ps, [80, 80, 40, 60]));
    });

    test('updateDoubles re-runs scoring', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      final undoubled = c.read(calculatorProvider).result!.scores;
      n.updateDoubles(
        DoubleMatrix.empty().withState(ps[0].id, ps[1].id, DoubleState.doubled),
      );
      final doubled = c.read(calculatorProvider).result!.scores;
      // With equal counts (4,4) on doubled pair, scores should still match.
      expect(doubled[ps[0].id], undoubled[ps[0].id]);
      expect(doubled[ps[1].id], undoubled[ps[1].id]);
    });
  });

  group('hasMeaningfulPendingInput', () {
    test('false when only zero counts have been entered', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs()); // pre-fills zeros
      n.discardGame();
      n.selectGame(const Clubs());
      n.deselectGame();
      expect(c.read(calculatorProvider).hasMeaningfulPendingInput, isFalse);
    });

    test('true after some counts are entered and game is paused', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0]))); // sum 3
      n.deselectGame();
      final s = c.read(calculatorProvider);
      expect(s.hasPendingGame, isTrue);
      expect(s.hasMeaningfulPendingInput, isTrue);
    });
  });

  group('deselectGame: completed round flow', () {
    test('completing a round advances dealer and round number', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      final s = c.read(calculatorProvider);
      expect(s.history.length, 1);
      expect(s.dealerIndex, 1);
      expect(s.roundNumber, 2);
      expect(s.selectedGame, isNull);
    });

    test('completed round is preserved in history', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();
      final state = c.read(calculatorProvider);
      final r = state.history.first;
      expect(r.game.id, 'duck');
      expect(
        [for (final p in state.players) r.scoresByPlayer[p.id]],
        [-40, -30, -50, -10],
      );
    });
  });

  group('discardGame', () {
    test('discardGame clears selection without saving pending', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.discardGame();
      final s = c.read(calculatorProvider);
      expect(s.selectedGame, isNull);
      expect(s.hasPendingGame, isFalse);
    });
  });

  group('Resuming pending game', () {
    test('selecting same pending game restores partial input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 2, 0, 0])));
      n.deselectGame(); // saved as pending
      expect(c.read(calculatorProvider).hasPendingGame, isTrue);
      n.selectGame(const Clubs()); // resume
      final s = c.read(calculatorProvider);
      expect((s.input! as CountsInput).counts, _t(ps, [3, 2, 0, 0]));
      expect(s.hasPendingGame, isFalse);
    });

    test('selecting a different game does NOT restore pending input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 2, 0, 0])));
      n.deselectGame();
      n.selectGame(const Duck());
      final s = c.read(calculatorProvider);
      expect(
        (s.input! as CountsInput).counts.values.every((v) => v == 0),
        isTrue,
      );
    });
  });

  group('deleteLastRound', () {
    test('removes the last completed round and rolls back dealer/round', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();
      expect(c.read(calculatorProvider).history.length, 2);
      n.deleteLastRound();
      final s = c.read(calculatorProvider);
      expect(s.history.length, 1);
      expect(s.dealerIndex, 1);
      expect(s.roundNumber, 2);
    });

    test('does nothing when history is empty', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.deleteLastRound();
      expect(c.read(calculatorProvider).history, isEmpty);
    });
  });

  group('Edit-existing-round flow', () {
    test(
      'restoreRound leaves history intact; deselectGame replaces in place',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final ps = c.read(calculatorProvider).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
        n.deselectGame();

        final clubsRound = c.read(calculatorProvider).history.first;
        n.restoreRound(clubsRound);
        var s = c.read(calculatorProvider);
        expect(s.isEditingExistingRound, isTrue);
        expect(s.history.length, 2);
        expect(s.history[1].game.id, 'duck');
        expect(s.editingRoundIndex, 0);
        expect(s.selectedGame!.id, 'clubs');

        n.updateInput(CountsInput(_t(ps, [3, 4, 3, 3])));
        n.deselectGame();

        s = c.read(calculatorProvider);
        expect(s.isEditingExistingRound, isFalse);
        expect(s.history.length, 2);
        expect(s.history[0].game.id, 'clubs');
        expect(
          (s.history[0].input as CountsInput).counts,
          _t(ps, [3, 4, 3, 3]),
        );
        expect(s.history[1].game.id, 'duck');
        expect(
          (s.history[1].input as CountsInput).counts,
          _t(ps, [4, 3, 5, 1]),
        );
      },
    );

    test('editing an older round + cancel keeps every later round intact', () {
      // Regression for the silent multi-round wipe.
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();

      final clubsRound = c.read(calculatorProvider).history.first;
      n.restoreRound(clubsRound);
      n.updateInput(CountsInput(_t(ps, [1, 1, 1, 1])));
      expect(c.read(calculatorProvider).inputState, isNot(InputState.complete));
      expect(c.read(calculatorProvider).isEditingLastRound, isFalse);
      expect(c.read(calculatorProvider).canRollbackWithPartial, isFalse);

      n.cancelEditRound();
      final s = c.read(calculatorProvider);
      expect(s.history.length, 2);
      expect((s.history[0].input as CountsInput).counts, _t(ps, [4, 4, 2, 3]));
      expect((s.history[1].input as CountsInput).counts, _t(ps, [4, 3, 5, 1]));
    });

    test(
      'editing the LAST round + rollbackLastRound only removes that round',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final ps = c.read(calculatorProvider).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
        n.deselectGame();

        final duckRound = c.read(calculatorProvider).history.last;
        n.restoreRound(duckRound);
        expect(c.read(calculatorProvider).isEditingLastRound, isTrue);
        expect(c.read(calculatorProvider).canRollbackWithPartial, isTrue);
        n.updateInput(CountsInput(_t(ps, [0, 0, 0, 0]))); // make incomplete
        n.rollbackLastRound();
        final s = c.read(calculatorProvider);
        expect(s.history.length, 1);
        expect(s.history.first.game.id, 'clubs');
        expect(s.roundNumber, 2);
        expect(s.dealerIndex, 1);
      },
    );

    test('pending game survives an edit of any round', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // saved as pending
      expect(c.read(calculatorProvider).hasPendingGame, isTrue);

      n.restoreRound(c.read(calculatorProvider).history.first);
      expect(c.read(calculatorProvider).pending, isA<ActivePendingRound>());
      n.cancelEditRound();
      final s = c.read(calculatorProvider);
      expect(s.hasPendingGame, isTrue);
      expect((s.pending as ActivePendingRound).game.id, 'duck');
      expect(
        ((s.pending as ActivePendingRound).input as CountsInput).counts,
        _t(ps, [3, 0, 0, 0]),
      );
    });

    test('cancelEditRound restores the slot to the pre-edit state', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();

      final beforeEdit = c.read(calculatorProvider);
      n.restoreRound(beforeEdit.history.first);
      n.updateInput(CountsInput(_t(ps, [13, 0, 0, 0]))); // change input
      n.cancelEditRound();

      final after = c.read(calculatorProvider);
      expect(after.isEditingExistingRound, isFalse);
      expect(after.history.length, 1);
      expect(
        (after.history.first.input as CountsInput).counts,
        _t(ps, [4, 4, 2, 3]),
      );
    });

    test('hasActiveChanges is false when nothing was changed during edit', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.restoreRound(c.read(calculatorProvider).history.first);
      expect(c.read(calculatorProvider).hasActiveChanges, isFalse);
    });

    test('hasActiveChanges is true after modifying input during edit', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final ps = c.read(calculatorProvider).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.restoreRound(c.read(calculatorProvider).history.first);
      n.updateInput(CountsInput(_t(ps, [5, 4, 2, 2])));
      expect(c.read(calculatorProvider).hasActiveChanges, isTrue);
    });
  });

  group('startNewGame / buildSession / loadSession', () {
    test('buildSession returns null before startNewGame', () {
      final c = makeContainer();
      expect(c.read(calculatorProvider.notifier).buildSession(), isNull);
    });

    test('startNewGame assigns names, dealer, id and timestamps', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 2,
      );
      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['A', 'B', 'C', 'D']);
      expect(s.dealerIndex, 2);
      expect(s.sessionId, isNotEmpty);
      expect(s.createdAt, isNotNull);
      expect(s.updatedAt, isNotNull);
    });

    test('buildSession reflects history and pending game', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame();

      final session = n.buildSession()!;
      expect(session.displayedPlayerNames, ['A', 'B', 'C', 'D']);
      expect(session.rounds.length, 1);
      expect(session.rounds.first.game.id, 'clubs');
      expect(session.pendingRound, isNotNull);
      expect(session.pendingRound!.gameId, 'duck');
      expect(
        (session.pendingRound!.input as CountsInput).counts,
        _t(ps, [3, 0, 0, 0]),
      );
    });

    test('loadSession restores history and pending game', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame();

      final session = n.buildSession()!;

      n.reset();
      expect(c.read(calculatorProvider).playerNames, ['', '', '', '']);
      n.loadSession(session);

      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['A', 'B', 'C', 'D']);
      expect(s.history.length, 1);
      expect(s.history.first.game.id, 'clubs');
      expect(s.hasPendingGame, isTrue);
      expect((s.pending as ActivePendingRound).game.id, 'duck');
      expect(
        ((s.pending as ActivePendingRound).input as CountsInput).counts,
        _t(ps, [3, 0, 0, 0]),
      );
    });

    test('switching sessions flushes the outgoing autosave so last-second '
        'pending edits are not lost to the 400ms debounce window', () async {
      final c = makeContainer();
      await c.read(gameHistoryProvider.future);
      final n = c.read(calculatorProvider.notifier);

      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final sessionAId = c.read(calculatorProvider).sessionId;
      final ps = c.read(calculatorProvider).players;
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // saved as pending; autosave is debounced 400ms.

      final now = DateTime.now();
      final pB = _makePlayers(['W', 'X', 'Y', 'Z']);
      final sessionB = GameSession(
        id: 'session-B',
        createdAt: now,
        updatedAt: now,
        players: pB,
        firstDealerId: pB[0].id,
        rounds: const [],
      );
      n.loadSession(sessionB);

      await pumpEventQueue();

      final sessions = await c.read(gameHistoryProvider.future);
      final savedA = sessions.firstWhere((s) => s.id == sessionAId);
      expect(savedA.pendingRound, isNotNull);
      expect(savedA.pendingRound!.gameId, 'duck');
      expect(
        (savedA.pendingRound!.input as CountsInput).counts,
        _t(ps, [3, 0, 0, 0]),
      );
    });
  });

  group('reset', () {
    test('reset clears all session state', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['A', '', '', '']), dealerIndex: 0);
      n.reset();
      final s = c.read(calculatorProvider);
      expect(s.sessionId, '');
      expect(s.playerNames, ['', '', '', '']);
      expect(s.history, isEmpty);
    });
  });

  group('inputState edge cases', () {
    test(
      'negative count is currently considered valid as long as the sum matches',
      () {
        // [-1, 14, 0, 0] sums to 13 → inputState is complete today.
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final ps = c.read(calculatorProvider).players;
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [-1, 14, 0, 0])));
        expect(c.read(calculatorProvider).inputState, InputState.complete);
      },
    );
  });

  group('Edit-existing-round flow — additional coverage', () {
    test(
      'edit last round + save with no changes leaves dealer/round/history unchanged',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final ps = c.read(calculatorProvider).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
        n.deselectGame();

        final before = c.read(calculatorProvider);
        final dealerBefore = before.dealerIndex;
        final roundBefore = before.roundNumber;
        final lenBefore = before.history.length;

        n.restoreRound(before.history.last);
        n.deselectGame();

        final s = c.read(calculatorProvider);
        expect(s.dealerIndex, dealerBefore);
        expect(s.roundNumber, roundBefore);
        expect(s.history.length, lenBefore);
        expect(s.isEditingExistingRound, isFalse);
      },
    );
  });

  group('loadSession — no pending', () {
    test(
      'history with last dealer=1 → dealerIndex=2, chooserIndex=3, roundNumber=3',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(
          players: _makePlayers(['A', 'B', 'C', 'D']),
          dealerIndex: 0,
        );
        final ps = c.read(calculatorProvider).players;
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
        n.deselectGame();

        final session = n.buildSession()!;
        expect(session.pendingRound, isNull);

        n.reset();
        n.loadSession(session);
        final s = c.read(calculatorProvider);
        expect(s.dealerIndex, 2);
        expect(s.chooserIndex, 3);
        expect(s.roundNumber, 3);
        expect(s.pending, isA<NoPendingRound>());
        expect(s.hasPendingGame, isFalse);
      },
    );
  });

  group('hasActiveChanges — chooser changes', () {
    test('chooser-only deviation from default returns true', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.setChooser(2);
      expect(c.read(calculatorProvider).hasActiveChanges, isTrue);
    });

    test('bare selectGame with no other changes returns false', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      expect(c.read(calculatorProvider).hasActiveChanges, isFalse);
    });
  });

  group('setPlayersAndDealer — reorder + dealer', () {
    test('moving the dealer up keeps dealer pointing at same person', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      n.setDealer(2); // dealer = C
      final players = List<Player>.from(c.read(calculatorProvider).players);
      final moved = players.removeAt(2);
      players.insert(0, moved);
      n.setPlayersAndDealer(players, 0);
      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['C', 'A', 'B', 'D']);
      expect(s.dealerIndex, 0);
    });

    test('setPlayersAndDealer updates players and dealer index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      final players = List<Player>.from(c.read(calculatorProvider).players);
      final moved = players.removeAt(2);
      players.insert(0, moved);
      n.setPlayersAndDealer(players, 1);
      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['C', 'A', 'B', 'D']);
      expect(s.dealerIndex, 1);
    });
  });

  group('hasMeaningfulPendingInput — recipient games', () {
    test(
      'RecipientInputDescriptor with a recipient set is meaningful (loaded)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final pA = _makePlayers(['A', 'B', 'C', 'D']);
        final session = GameSession(
          id: 's1',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          players: pA,
          firstDealerId: pA[0].id,
          rounds: const [],
          pendingRound: PendingRound(
            gameId: 'kingOfHearts',
            gameName: 'Hartenheer',
            chooserId: pA[1].id,
            input: RecipientInput([pA[0].id]),
          ),
        );
        n.loadSession(session);
        expect(c.read(calculatorProvider).hasMeaningfulPendingInput, isTrue);
      },
    );

    test(
      'RecipientInputDescriptor with only one slot set is meaningful (loaded)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final pA = _makePlayers(['A', 'B', 'C', 'D']);
        final session = GameSession(
          id: 's1',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          players: pA,
          firstDealerId: pA[0].id,
          rounds: const [],
          pendingRound: PendingRound(
            gameId: 'seventhAndThirteenth',
            gameName: '7e / 13e',
            chooserId: pA[1].id,
            input: RecipientInput([null, pA[0].id]),
          ),
        );
        n.loadSession(session);
        expect(c.read(calculatorProvider).hasMeaningfulPendingInput, isTrue);
      },
    );
  });

  group('StarterVariant / HeartsVariant', () {
    test(
      'defaults to dealerStarts / onlyAfterPlayedHeart after startNewGame',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(
          players: _makePlayers(['A', 'B', 'C', 'D']),
          dealerIndex: 0,
        );
        final s = c.read(calculatorProvider);
        expect(s.ruleVariants.starterVariant, StarterVariant.dealerStarts);
        expect(
          s.ruleVariants.heartsVariant,
          HeartsVariant.onlyAfterPlayedHeart,
        );
      },
    );

    test('startNewGame accepts explicit variant values', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
        ruleVariants: const RuleVariants(
          starterVariant: StarterVariant.oppositeChooserStarts,
          heartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      final s = c.read(calculatorProvider);
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('setStarterVariant / setHeartsVariant update state', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      n.setStarterVariant(StarterVariant.oppositeChooserStarts);
      n.setHeartsVariant(HeartsVariant.graduatedUnlock);
      final s = c.read(calculatorProvider);
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('starterIndex reflects the active StarterVariant', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final players = _makePlayers(['A', 'B', 'C', 'D']);
      n.startNewGame(players: players, dealerIndex: 0);
      // Chooser is seat 1 (left of dealer 0).
      final chooserIdx = c.read(calculatorProvider).chooserIndex;

      n.setStarterVariant(StarterVariant.dealerStarts);
      expect(
        c.read(calculatorProvider).starterIndex,
        dealerIndexFor(chooserIdx),
      );

      n.setStarterVariant(StarterVariant.oppositeChooserStarts);
      expect(
        c.read(calculatorProvider).starterIndex,
        starterIndexFor(chooserIdx, StarterVariant.oppositeChooserStarts),
      );
    });

    test('loadSession restores both variant fields', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final players = _makePlayers(['A', 'B', 'C', 'D']);
      final saved = GameSession(
        id: 'v-load',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        players: players,
        firstDealerId: players[0].id,
        rounds: const [],
        ruleVariants: const RuleVariants(
          starterVariant: StarterVariant.oppositeChooserStarts,
          heartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      n.loadSession(saved);
      final s = c.read(calculatorProvider);
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('buildSession preserves both variant fields', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
        ruleVariants: const RuleVariants(
          starterVariant: StarterVariant.oppositeChooserStarts,
          heartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      final built = n.buildSession()!;
      expect(
        built.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(built.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test(
      'starterIndex uses playerCount-safe modular arithmetic (no out-of-bounds)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final players = _makePlayers(['A', 'B', 'C', 'D']);
        n.startNewGame(
          players: players,
          dealerIndex: 0,
          ruleVariants: const RuleVariants(
            starterVariant: StarterVariant.oppositeChooserStarts,
          ),
        );
        // For every chooser position the starter index must be in [0, playerCount).
        for (var dealer = 0; dealer < playerCount; dealer++) {
          n.setDealer(dealer);
          final idx = c.read(calculatorProvider).starterIndex;
          expect(idx, inInclusiveRange(0, playerCount - 1));
        }
      },
    );
  });

  group('deleteLastRound while pending game present', () {
    test(
      'deleting last round keeps the pending game intact (current behavior)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final ps = c.read(calculatorProvider).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
        n.deselectGame();
        expect(c.read(calculatorProvider).hasPendingGame, isTrue);

        n.deleteLastRound();
        final s = c.read(calculatorProvider);
        expect(s.history, isEmpty);
        expect(s.hasPendingGame, isTrue);
        expect((s.pending as ActivePendingRound).game.id, 'duck');
      },
    );
  });
}
