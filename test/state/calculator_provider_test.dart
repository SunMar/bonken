import 'dart:async';

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

/// A round-less [GameSession] fixture for the `loadSession` tests — collapses the
/// repeated id/timestamps/firstDealer boilerplate. The dealer is [players].first;
/// pass a [pendingRound] or [ruleVariants] to exercise those paths.
GameSession _session(
  List<Player> players, {
  String id = 's1',
  PendingRound? pendingRound,
  RuleVariants ruleVariants = const RuleVariants(),
}) {
  final dt = DateTime(2024);
  return GameSession(
    id: id,
    createdAt: dt,
    updatedAt: dt,
    scoredAt: dt,
    players: players,
    firstDealerId: players.first.id,
    rounds: const [],
    pendingRound: pendingRound,
    ruleVariants: ruleVariants,
  );
}

ProviderContainer makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// A [GameHistoryNotifier] whose [saveGame] blocks on [gate] before the real
/// upsert — lets a test hold an autosave genuinely "in flight" while a delete
/// runs, to exercise the resurrection-race guard.
class _BlockingGameHistoryNotifier extends GameHistoryNotifier {
  final gate = Completer<void>();

  @override
  Future<void> saveGame(GameSession session) async {
    await gate.future;
    return super.saveGame(session);
  }
}

void main() {
  setUpPrefs();
  initializeWidgets();

  group('Initial state', () {
    test('build returns NoSession', () {
      final c = makeContainer();
      expect(c.read(calculatorProvider), isA<NoSession>());
    });
  });

  group('setPlayerName / setDealer / setChooser', () {
    test('setPlayerName updates only the given index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setPlayerName(0, 'Alice');
      n.setPlayerName(2, 'Carol');
      expect((c.read(calculatorProvider) as ActiveSession).playerNames, [
        'Alice',
        '',
        'Carol',
        '',
      ]);
    });

    test('setDealer updates dealer index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setDealer(2);
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.dealerIndex, 2);
      expect(s.roundNumber, 1);
      expect(s.history, isEmpty);
    });

    test('setChooser updates the chooser index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setChooser(3);
      expect((c.read(calculatorProvider) as ActiveSession).chooserIndex, 3);
    });
  });

  group('selectGame', () {
    test('selecting a counts game pre-fills with zeros', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.selectGame(const Clubs());
      final s = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.selectGame(const KingOfHearts());
      expect(
        ((c.read(calculatorProvider) as ActiveSession).input! as RecipientInput)
            .recipients,
        [null],
      );
    });

    test('selecting two-slot recipient game leaves both slots null', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.selectGame(const SeventhAndThirteenth());
      expect(
        ((c.read(calculatorProvider) as ActiveSession).input! as RecipientInput)
            .recipients,
        [null, null],
      );
    });

    test('chooser defaults to player left of dealer', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setDealer(2);
      n.selectGame(const Clubs());
      expect((c.read(calculatorProvider) as ActiveSession).chooserIndex, 3);
    });
  });

  group('updateInput / recalculate', () {
    test('partial counts produce a partialResult, not a final result', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 3, 2, 0]))); // sum 9 < 13
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.result, isNull);
      expect(s.partialResult, isNotNull);
      expect(s.inputState, InputState.partial);
    });

    test('complete counts produce a final result', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3]))); // sum 13
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.inputState, InputState.complete);
      expect(s.result, isNotNull);
      expect(s.partialResult, isNull);
      expect(s.result!.scores, _t(ps, [80, 80, 40, 60]));
    });

    test('half-filled 7e/13e (one of two slots) produces a partialResult', () {
      // Recipient games are usually empty-or-complete, but the two-slot
      // 7e/13e game is `partial` with exactly one slot filled, so it shows a
      // live preview just like a partway-entered counts game.
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const SeventhAndThirteenth());
      // Fill only the 7th-trick slot; the 13th stays null.
      n.updateInput(RecipientInput([ps[0].id, null]));
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.inputState, InputState.partial);
      expect(s.result, isNull);
      expect(s.partialResult, isNotNull);
      // The one chosen recipient already shows the -50 live preview.
      expect(s.partialResult!.scores[ps[0].id], -50);
    });

    test('updateDoubles re-runs scoring', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      final undoubled =
          (c.read(calculatorProvider) as ActiveSession).result!.scores;
      n.updateDoubles(
        const DoubleMatrix().withState(ps[0].id, ps[1].id, DoubleState.doubled),
      );
      final doubled =
          (c.read(calculatorProvider) as ActiveSession).result!.scores;
      // With equal counts (4,4) on doubled pair, scores should still match.
      expect(doubled[ps[0].id], undoubled[ps[0].id]);
      expect(doubled[ps[1].id], undoubled[ps[1].id]);
    });

    test(
      'redoubled pair on unequal counts shifts twice through the notifier',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [5, 2, 3, 3]))); // sum 13
        n.updateDoubles(
          const DoubleMatrix().withState(
            ps[0].id,
            ps[1].id,
            DoubleState.redoubled,
          ),
        );
        // Redoubled (multiplier 2) on the 5-vs-2 pair (diff 3):
        //   effective[0] = 5 + (5-2)*2 = 11 → 220
        //   effective[1] = 2 + (2-5)*2 = -4 → -80
        // The other two players are untouched and Σ stays +260.
        final scores =
            (c.read(calculatorProvider) as ActiveSession).result!.scores;
        expect(scores, _t(ps, [220, -80, 60, 60]));
        expect(scores.values.fold(0, (a, b) => a + b), 260);
      },
    );
  });

  group('hasMeaningfulPendingInput', () {
    test('false when only zero counts have been entered', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.selectGame(const Clubs()); // pre-fills zeros
      n.discardGame();
      n.selectGame(const Clubs());
      n.deselectGame();
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasMeaningfulPendingInput,
        isFalse,
      );
    });

    test('true after some counts are entered and game is paused', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0]))); // sum 3
      n.deselectGame();
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.hasPendingGame, isTrue);
      expect(s.hasMeaningfulPendingInput, isTrue);
    });
  });

  group('deselectGame: completed round flow', () {
    test('completing a round advances dealer and round number', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.history.length, 1);
      expect(s.dealerIndex, 1);
      expect(s.roundNumber, 2);
      expect(s.selectedGame, isNull);
    });

    test('completed round is preserved in history', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();
      final state = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.discardGame();
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.selectedGame, isNull);
      expect(s.hasPendingGame, isFalse);
    });

    test(
      'discardGame clears pending when discarding a resumed pending game',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
        n.deselectGame(); // stash as pending
        expect(
          (c.read(calculatorProvider) as ActiveSession).hasPendingGame,
          isTrue,
        );
        n.selectGame(const Clubs()); // resume
        n.discardGame(); // discard the pending round
        expect(
          (c.read(calculatorProvider) as ActiveSession).hasPendingGame,
          isFalse,
        );
      },
    );
  });

  group('exitPendingSlot', () {
    test('exitPendingSlot preserves pending stash with latest input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 2, 0, 0])));
      n.exitPendingSlot();
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.selectedGame, isNull);
      expect(s.hasPendingGame, isTrue);
      final p = s.pending as ActivePendingRound;
      expect(p.game.id, 'clubs');
      expect((p.input! as CountsInput).counts, _t(ps, [3, 2, 0, 0]));
    });
  });

  group('Resuming pending game', () {
    test('selecting same pending game restores partial input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 2, 0, 0])));
      n.deselectGame(); // saved as pending
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasPendingGame,
        isTrue,
      );
      n.selectGame(const Clubs()); // resume
      final s = c.read(calculatorProvider) as ActiveSession;
      expect((s.input! as CountsInput).counts, _t(ps, [3, 2, 0, 0]));
      // pending stash is kept while actively editing — hasPendingGame stays true
      expect(s.hasPendingGame, isTrue);
    });

    test('selecting a different game does NOT restore pending input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 2, 0, 0])));
      n.deselectGame();
      n.selectGame(const Duck());
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(
        (s.input! as CountsInput).counts.values.every((v) => v == 0),
        isTrue,
      );
    });

    test('updateInput writes through to ActivePendingRound.input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [3, 2, 0, 0])));
      final p =
          (c.read(calculatorProvider) as ActiveSession).pending
              as ActivePendingRound;
      expect((p.input! as CountsInput).counts, _t(ps, [3, 2, 0, 0]));
    });

    test('updateDoubles writes through to ActivePendingRound.doubles', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      final dm = const DoubleMatrix().withPair(
        ps[0].id,
        ps[1].id,
        DoubleState.doubled,
        initiator: ps[0].id,
      );
      n.updateDoubles(dm);
      final p =
          (c.read(calculatorProvider) as ActiveSession).pending
              as ActivePendingRound;
      expect(p.doubles, dm);
    });
  });

  group('deleteLastRound', () {
    test('removes the last completed round and rolls back dealer/round', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();
      expect((c.read(calculatorProvider) as ActiveSession).history.length, 2);
      n.deleteLastRound(2);
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.history.length, 1);
      expect(s.dealerIndex, 1);
      expect(s.roundNumber, 2);
    });

    test('does nothing when history is empty', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.deleteLastRound(1);
      expect((c.read(calculatorProvider) as ActiveSession).history, isEmpty);
    });

    test('no-ops when roundNumber does not match the last round', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();
      expect((c.read(calculatorProvider) as ActiveSession).history.length, 2);

      // The last round is round 2; asking to delete round 1 (e.g. a stale
      // confirm dialog) must leave history untouched rather than drop round 2.
      n.deleteLastRound(1);
      expect((c.read(calculatorProvider) as ActiveSession).history.length, 2);
    });
  });

  group('Edit-existing-round flow', () {
    test(
      'restoreRound leaves history intact; deselectGame replaces in place',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
        n.deselectGame();

        final clubsRound =
            (c.read(calculatorProvider) as ActiveSession).history.first;
        n.restoreRound(clubsRound);
        var s = c.read(calculatorProvider) as ActiveSession;
        expect(s.isEditingExistingRound, isTrue);
        expect(s.history.length, 2);
        expect(s.history[1].game.id, 'duck');
        expect(s.editingRoundIndex, 0);
        expect(s.selectedGame!.id, 'clubs');

        n.updateInput(CountsInput(_t(ps, [3, 4, 3, 3])));
        n.deselectGame();

        s = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
      n.deselectGame();

      final clubsRound =
          (c.read(calculatorProvider) as ActiveSession).history.first;
      n.restoreRound(clubsRound);
      n.updateInput(CountsInput(_t(ps, [1, 1, 1, 1])));
      expect(
        (c.read(calculatorProvider) as ActiveSession).inputState,
        isNot(InputState.complete),
      );
      // Editing the first (non-last) of two rounds.
      expect(
        (c.read(calculatorProvider) as ActiveSession).editingRoundIndex,
        0,
      );

      n.cancelEditRound();
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.history.length, 2);
      expect((s.history[0].input as CountsInput).counts, _t(ps, [4, 4, 2, 3]));
      expect((s.history[1].input as CountsInput).counts, _t(ps, [4, 3, 5, 1]));
    });

    test('pending game survives an edit of any round', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // saved as pending
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasPendingGame,
        isTrue,
      );

      n.restoreRound(
        (c.read(calculatorProvider) as ActiveSession).history.first,
      );
      expect(
        (c.read(calculatorProvider) as ActiveSession).pending,
        isA<ActivePendingRound>(),
      );
      n.cancelEditRound();
      final s = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();

      final beforeEdit = c.read(calculatorProvider) as ActiveSession;
      n.restoreRound(beforeEdit.history.first);
      n.updateInput(CountsInput(_t(ps, [13, 0, 0, 0]))); // change input
      n.cancelEditRound();

      final after = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.restoreRound(
        (c.read(calculatorProvider) as ActiveSession).history.first,
      );
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasActiveChanges,
        isFalse,
      );
    });

    test('hasActiveChanges is true after modifying input during edit', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.restoreRound(
        (c.read(calculatorProvider) as ActiveSession).history.first,
      );
      n.updateInput(CountsInput(_t(ps, [5, 4, 2, 2])));
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasActiveChanges,
        isTrue,
      );
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 2,
      );
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.playerNames, ['A', 'B', 'C', 'D']);
      expect(s.dealerIndex, 2);
      expect(s.sessionId, isNotEmpty);
      expect(s.createdAt, isNotNull);
      expect(s.updatedAt, isNotNull);
    });

    test('buildSession reflects history and pending game', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame();

      final session = n.buildSession()!;

      n.reset();
      expect(c.read(calculatorProvider), isA<NoSession>());
      n.loadSession(session);

      final s = c.read(calculatorProvider) as ActiveSession;
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

    test('loadSession throws on an unknown pending game id (fail loud)', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      final players = _makePlayers(['A', 'B', 'C', 'D']);
      final bad = _session(
        players,
        id: kGameId1,
        pendingRound: PendingRound(
          gameId: 'not-a-real-game',
          chooserId: players[1].id,
        ),
      );
      // A real load can't carry an unknown id (PendingRound.fromJson rejects
      // it); a hand-built session must fail loud, not silently drop the stash.
      expect(() => n.loadSession(bad), throwsStateError);
    });

    test('switching sessions flushes the outgoing autosave so last-second '
        'pending edits are not lost to the 400ms debounce window', () async {
      final c = makeContainer();
      await c.read(gameHistoryProvider.future);
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);

      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final sessionAId =
          (c.read(calculatorProvider) as ActiveSession).sessionId;
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // saved as pending; autosave is debounced 400ms.

      final now = DateTime.now();
      final pB = _makePlayers(['W', 'X', 'Y', 'Z']);
      final sessionB = GameSession(
        id: 'session-B',
        createdAt: now,
        updatedAt: now,
        scoredAt: now,
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

    test('startNewGame flushes the outgoing autosave so last-second '
        'pending edits are not lost to the 400ms debounce window', () async {
      final c = makeContainer();
      await c.read(gameHistoryProvider.future);
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final sessionAId =
          (c.read(calculatorProvider) as ActiveSession).sessionId;
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // saved as pending; autosave is debounced 400ms.

      // Start a brand-new game before the 400ms timer fires.
      n.startNewGame(
        players: _makePlayers(['W', 'X', 'Y', 'Z']),
        dealerIndex: 0,
      );

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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.startNewGame(players: _makePlayers(['A', '', '', '']), dealerIndex: 0);
      n.reset();
      expect(c.read(calculatorProvider), isA<NoSession>());
    });
  });

  group('autoDispose flush', () {
    // testWidgets is required here: initializeWidgets() installs FakeAsync, so
    // Timer(Duration.zero) — used by Riverpod's dispose scheduler — won't fire
    // in a plain test() without an explicit tester.pump() to advance fake time.
    testWidgets('pending autosave is written when the last listener drops', (
      tester,
    ) async {
      final c = makeContainer();
      await c.read(gameHistoryProvider.future);
      // Hold an explicit subscription so the autoDispose provider stays alive.
      final sub = c.listen<CalculatorState>(calculatorProvider, (_, _) {});
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final sessionId = (c.read(calculatorProvider) as ActiveSession).sessionId;
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // debounced autosave scheduled

      sub.close(); // drop last listener → schedules autoDispose Timer(Duration.zero)
      // pump() advances FakeAsync time by one tick, firing Riverpod's
      // Timer(Duration.zero) dispose callback which triggers onDispose.
      // A second pump drains the async saveGame chain.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final sessions = await c.read(gameHistoryProvider.future);
      final saved = sessions.firstWhere((s) => s.id == sessionId);
      expect(saved.pendingRound, isNotNull);
      expect(saved.pendingRound!.gameId, 'duck');
      expect(
        (saved.pendingRound!.input as CountsInput).counts,
        _t(ps, [3, 0, 0, 0]),
      );
    });
  });

  group('cancelPendingAutosave', () {
    test(
      'cancelPendingAutosave prevents the debounced save from persisting data',
      () async {
        final c = makeContainer();
        await c.read(gameHistoryProvider.future);
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(
          players: _makePlayers(['A', 'B', 'C', 'D']),
          dealerIndex: 0,
        );
        final sessionId =
            (c.read(calculatorProvider) as ActiveSession).sessionId;
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
        n.deselectGame(); // debounced autosave scheduled

        await n.cancelPendingAutosave(); // cancels timer + joins in-flight

        await pumpEventQueue();

        final sessions = await c.read(gameHistoryProvider.future);
        expect(sessions.any((s) => s.id == sessionId), isFalse);
      },
    );

    // testWidgets: initializeWidgets() installs FakeAsync so the 400ms debounce
    // timer can be fired deterministically via tester.pump.
    testWidgets('delete is not resurrected by an in-flight autosave', (
      tester,
    ) async {
      final blocking = _BlockingGameHistoryNotifier();
      final c = ProviderContainer(
        overrides: [gameHistoryProvider.overrideWith(() => blocking)],
      );
      addTearDown(c.dispose);
      await c.read(gameHistoryProvider.future);
      final sub = c.listen<CalculatorState>(calculatorProvider, (_, _) {});
      addTearDown(sub.close);
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      final sessionId = (c.read(calculatorProvider) as ActiveSession).sessionId;
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Duck());
      n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
      n.deselectGame(); // schedules the debounced autosave

      // Fire the debounce: saveGame starts and blocks on the gate, so the write
      // is genuinely in flight when the delete runs.
      await tester.pump(const Duration(milliseconds: 400));

      // Delete flow: cancelPendingAutosave must JOIN the in-flight save, then
      // deleteGame removes whatever it wrote — no resurrection.
      final deleteFlow = () async {
        await n.cancelPendingAutosave();
        await c.read(gameHistoryProvider.notifier).deleteGame(sessionId);
      }();

      // Let the in-flight save complete; cancelAndJoin unblocks and the delete
      // runs strictly after it.
      blocking.gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await deleteFlow;

      final sessions = await c.read(gameHistoryProvider.future);
      expect(sessions.any((s) => s.id == sessionId), isFalse);
    });
  });

  group('inputState edge cases', () {
    test(
      'negative count is currently considered valid as long as the sum matches',
      () {
        // [-1, 14, 0, 0] sums to 13 → inputState is complete today.
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [-1, 14, 0, 0])));
        expect(
          (c.read(calculatorProvider) as ActiveSession).inputState,
          InputState.complete,
        );
      },
    );
  });

  group('Edit-existing-round flow — additional coverage', () {
    test(
      'edit last round + save with no changes leaves dealer/round/history unchanged',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [4, 3, 5, 1])));
        n.deselectGame();

        final before = c.read(calculatorProvider) as ActiveSession;
        final dealerBefore = before.dealerIndex;
        final roundBefore = before.roundNumber;
        final lenBefore = before.history.length;

        n.restoreRound(before.history.last);
        n.deselectGame();

        final s = c.read(calculatorProvider) as ActiveSession;
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
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        n.startNewGame(
          players: _makePlayers(['A', 'B', 'C', 'D']),
          dealerIndex: 0,
        );
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
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
        final s = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.setChooser(2);
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasActiveChanges,
        isTrue,
      );
    });

    test('bare selectGame with no other changes returns false', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setDealer(0);
      n.selectGame(const Clubs());
      expect(
        (c.read(calculatorProvider) as ActiveSession).hasActiveChanges,
        isFalse,
      );
    });
  });

  group('setPlayersAndDealer — reorder + dealer', () {
    test('moving the dealer up keeps dealer pointing at same person', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      n.setDealer(2); // dealer = C
      final players = List<Player>.from(
        (c.read(calculatorProvider) as ActiveSession).players,
      );
      final moved = players.removeAt(2);
      players.insert(0, moved);
      n.setPlayersAndDealer(players, 0);
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(s.playerNames, ['C', 'A', 'B', 'D']);
      expect(s.dealerIndex, 0);
    });

    test('setPlayersAndDealer updates players and dealer index', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      final players = List<Player>.from(
        (c.read(calculatorProvider) as ActiveSession).players,
      );
      final moved = players.removeAt(2);
      players.insert(0, moved);
      n.setPlayersAndDealer(players, 1);
      final s = c.read(calculatorProvider) as ActiveSession;
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
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final pA = _makePlayers(['A', 'B', 'C', 'D']);
        final session = _session(
          pA,
          pendingRound: PendingRound(
            gameId: 'kingOfHearts',
            chooserId: pA[1].id,
            input: RecipientInput([pA[0].id]),
          ),
        );
        n.loadSession(session);
        expect(
          (c.read(calculatorProvider) as ActiveSession)
              .hasMeaningfulPendingInput,
          isTrue,
        );
      },
    );

    test(
      'RecipientInputDescriptor with only one slot set is meaningful (loaded)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final pA = _makePlayers(['A', 'B', 'C', 'D']);
        final session = _session(
          pA,
          pendingRound: PendingRound(
            gameId: 'seventhAndThirteenth',
            chooserId: pA[1].id,
            input: RecipientInput([null, pA[0].id]),
          ),
        );
        n.loadSession(session);
        expect(
          (c.read(calculatorProvider) as ActiveSession)
              .hasMeaningfulPendingInput,
          isTrue,
        );
      },
    );
  });

  group('StarterVariant / HeartsVariant', () {
    test(
      'defaults to dealerStarts / onlyAfterPlayedHeart after startNewGame',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        n.startNewGame(
          players: _makePlayers(['A', 'B', 'C', 'D']),
          dealerIndex: 0,
        );
        final s = c.read(calculatorProvider) as ActiveSession;
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
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
        ruleVariants: const RuleVariants(
          starterVariant: StarterVariant.oppositeChooserStarts,
          heartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('setStarterVariant / setHeartsVariant update state', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      n.setStarterVariant(StarterVariant.oppositeChooserStarts);
      n.setHeartsVariant(HeartsVariant.graduatedUnlock);
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('starterIndex reflects the active StarterVariant', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final players = _makePlayers(['A', 'B', 'C', 'D']);
      n.startNewGame(players: players, dealerIndex: 0);
      // Chooser is seat 1 (left of dealer 0).
      final chooserIdx =
          (c.read(calculatorProvider) as ActiveSession).chooserIndex;

      n.setStarterVariant(StarterVariant.dealerStarts);
      expect(
        (c.read(calculatorProvider) as ActiveSession).starterIndex,
        dealerIndexFor(chooserIdx),
      );

      n.setStarterVariant(StarterVariant.oppositeChooserStarts);
      expect(
        (c.read(calculatorProvider) as ActiveSession).starterIndex,
        starterIndexFor(chooserIdx, StarterVariant.oppositeChooserStarts),
      );
    });

    test('loadSession restores both variant fields', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final players = _makePlayers(['A', 'B', 'C', 'D']);
      final saved = _session(
        players,
        id: 'v-load',
        ruleVariants: const RuleVariants(
          starterVariant: StarterVariant.oppositeChooserStarts,
          heartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      n.loadSession(saved);
      final s = c.read(calculatorProvider) as ActiveSession;
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(s.ruleVariants.heartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('buildSession preserves both variant fields', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
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
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
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
          final idx =
              (c.read(calculatorProvider) as ActiveSession).starterIndex;
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
        n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
        final ps = (c.read(calculatorProvider) as ActiveSession).players;
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput(CountsInput(_t(ps, [3, 0, 0, 0])));
        n.deselectGame();
        expect(
          (c.read(calculatorProvider) as ActiveSession).hasPendingGame,
          isTrue,
        );

        // Clubs is round 1 (the only completed round); Duck is pending.
        n.deleteLastRound(1);
        final s = c.read(calculatorProvider) as ActiveSession;
        expect(s.history, isEmpty);
        expect(s.hasPendingGame, isTrue);
        expect((s.pending as ActivePendingRound).game.id, 'duck');
      },
    );
  });

  group('activeSessionProvider', () {
    test('returns the ActiveSession while a game is active', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );

      final active = c.read(activeSessionProvider);
      // It is the same object as the underlying state, just narrowed.
      expect(active, same(c.read(calculatorProvider)));
      expect(active.playerNames, ['A', 'B', 'C', 'D']);
    });

    // Riverpod wraps the failing `state as ActiveSession` cast in a
    // ProviderException; match on the underlying cast message rather than the
    // wrapper type so the test doesn't couple to Riverpod internals.
    final throwsCastToActiveSession = throwsA(
      predicate<Object>(
        (e) => e.toString().contains('ActiveSession'),
        'a cast-to-ActiveSession failure',
      ),
    );

    test('throws when no session is active (NoSession)', () {
      final c = makeContainer();
      // Initial state is NoSession — the narrowing cast must throw rather than
      // hand back a wrong/empty session.
      expect(c.read(calculatorProvider), isA<NoSession>());
      expect(() => c.read(activeSessionProvider), throwsCastToActiveSession);
    });

    test('throws again after the session is reset to NoSession', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(
        players: _makePlayers(['A', 'B', 'C', 'D']),
        dealerIndex: 0,
      );
      expect(c.read(activeSessionProvider), isA<ActiveSession>());

      n.reset();
      expect(c.read(calculatorProvider), isA<NoSession>());
      expect(() => c.read(activeSessionProvider), throwsCastToActiveSession);
    });
  });

  group('scoredAt advancement contract', () {
    test('advances on round commit but NOT on player/name/rule edits', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      final scoredAt0 = (c.read(calculatorProvider) as ActiveSession).scoredAt;

      // Player / rule / name edits bump only updatedAt — scoredAt is preserved.
      n.setPlayerName(0, 'Alice');
      n.setStarterVariant(StarterVariant.oppositeChooserStarts);
      n.setHeartsVariant(HeartsVariant.graduatedUnlock);
      n.setGameName('Kerst');
      expect(
        (c.read(calculatorProvider) as ActiveSession).scoredAt,
        scoredAt0,
        reason: 'edits must leave scoredAt untouched',
      );

      // Committing a round advances scoredAt (set to now alongside the history
      // change). Real work elapsed since startNewGame, so the instant differs.
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3])));
      n.deselectGame();
      final committed = c.read(calculatorProvider) as ActiveSession;
      expect(committed.history, hasLength(1));
      expect(committed.scoredAt, isNot(scoredAt0));
    });
  });

  group('recalculate skip-emit', () {
    test('score-preserving recompute emits once; a score-changing one twice', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.startNewGame(players: _makePlayers(['', '', '', '']), dealerIndex: 0);
      final ps = (c.read(calculatorProvider) as ActiveSession).players;
      n.selectGame(const Clubs());
      n.updateInput(CountsInput(_t(ps, [4, 4, 2, 3]))); // complete result

      var emissions = 0;
      final sub = c.listen<CalculatorState>(calculatorProvider, (_, _) {
        emissions++;
      });
      addTearDown(sub.close);

      // Doubling an EQUAL-count pair (ps0 == ps1 == 4) changes the matrix but
      // not the scores: updateDoubles emits once (doubles), then _recalculate
      // sees the same ScoreResult and skips the second emit.
      n.updateDoubles(
        const DoubleMatrix().withState(ps[0].id, ps[1].id, DoubleState.doubled),
      );
      expect(emissions, 1);

      // Doubling an UNEQUAL pair (ps0 = 4 vs ps2 = 2) changes the scores, so
      // both the doubles change AND the new result emit — proving the skip above
      // was a real short-circuit, not a dropped recompute.
      n.updateDoubles(
        const DoubleMatrix().withState(ps[0].id, ps[2].id, DoubleState.doubled),
      );
      expect(emissions, 3);
    });
  });
}
