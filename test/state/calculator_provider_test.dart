import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/state/calculator_provider.dart';

import '../models/_double_matrix_helpers.dart';

ProviderContainer makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  // SharedPreferences is required by the autosave path triggered after
  // initSession(); we provide an in-memory mock for all tests.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  group('Initial state', () {
    test('build returns empty state', () {
      final c = makeContainer();
      final s = c.read(calculatorProvider);
      expect(s.sessionId, '');
      expect(s.dealerChosen, isFalse);
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

    test('setDealer marks dealerChosen and updates dealer', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(2);
      final s = c.read(calculatorProvider);
      expect(s.dealerIndex, 2);
      expect(s.dealerChosen, isTrue);
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
      expect(s.input['tricks'], [0, 0, 0, 0]);
      expect(s.doubles.hasAnyDouble, isFalse);
      expect(s.result, isNull);
    });

    test('selecting single-player game leaves selection null', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const KingOfHearts());
      expect(c.read(calculatorProvider).input['winner'], isNull);
    });

    test('selecting dual-player game leaves both selections null', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const SeventhAndThirteenth());
      final s = c.read(calculatorProvider);
      expect(s.input['trick7winner'], isNull);
      expect(s.input['trick13winner'], isNull);
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
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 3, 2, 0]); // sum 9 < 13
      final s = c.read(calculatorProvider);
      expect(s.result, isNull);
      expect(s.partialResult, isNotNull);
      expect(s.isInputValid, isFalse);
      expect(s.hasSomeInput, isTrue);
    });

    test('complete counts produce a final result', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]); // sum 13
      final s = c.read(calculatorProvider);
      expect(s.isInputValid, isTrue);
      expect(s.result, isNotNull);
      expect(s.partialResult, isNull);
      expect(s.result!.scores, {0: 80, 1: 80, 2: 40, 3: 60});
    });

    test('updateDoubles re-runs scoring', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      final undoubled = c.read(calculatorProvider).result!.scores;
      n.updateDoubles(
        DoubleMatrix.empty().withState(0, 1, DoubleState.doubled),
      );
      final doubled = c.read(calculatorProvider).result!.scores;
      // With equal counts (4,4) on doubled pair, scores should still match.
      expect(doubled[0], undoubled[0]);
      expect(doubled[1], undoubled[1]);
    });
  });

  group('hasMeaningfulPendingInput', () {
    test('false when only zero counts have been entered', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs()); // pre-fills [0,0,0,0]
      n.discardGame(); // Just to keep state sane
      // Now manually create a pending game scenario via deselectGame:
      n.selectGame(const Clubs());
      // counts still zero, deselect should NOT save as meaningful pending
      n.deselectGame();
      expect(c.read(calculatorProvider).hasMeaningfulPendingInput, isFalse);
    });

    test('true after some counts are entered and game is paused', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [3, 0, 0, 0]); // sum 3
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
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame(); // result was set → completed
      final s = c.read(calculatorProvider);
      expect(s.history.length, 1);
      expect(s.dealerIndex, 1);
      expect(s.roundNumber, 2);
      expect(s.selectedGame, isNull);
    });

    test('completed round is preserved in history', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Duck());
      n.updateInput('tricks', [4, 3, 5, 1]);
      n.deselectGame();
      final r = c.read(calculatorProvider).history.first;
      expect(r.game.id, 'duck');
      expect(r.result.scores, {0: -40, 1: -30, 2: -50, 3: -10});
    });
  });

  group('discardGame', () {
    test('discardGame clears selection without saving pending', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [3, 0, 0, 0]);
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
      n.selectGame(const Clubs());
      n.updateInput('tricks', [3, 2, 0, 0]);
      n.deselectGame(); // saved as pending
      expect(c.read(calculatorProvider).hasPendingGame, isTrue);
      n.selectGame(const Clubs()); // resume
      final s = c.read(calculatorProvider);
      expect(s.input['tricks'], [3, 2, 0, 0]);
      expect(s.hasPendingGame, isFalse);
    });

    test('selecting a different game does NOT restore pending input', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [3, 2, 0, 0]);
      n.deselectGame();
      n.selectGame(const Duck());
      final s = c.read(calculatorProvider);
      expect(s.input['tricks'], [0, 0, 0, 0]);
    });
  });

  group('deleteLastRound', () {
    test('removes the last completed round and rolls back dealer/round', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput('tricks', [4, 3, 5, 1]);
      n.deselectGame();
      // 2 rounds completed.
      expect(c.read(calculatorProvider).history.length, 2);
      n.deleteLastRound();
      final s = c.read(calculatorProvider);
      expect(s.history.length, 1);
      // After delete, dealer/round revert to the one stored on the deleted record.
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

  group('reorderRounds', () {
    test('reordering renumbers all rounds 1-based', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      // Play 3 rounds: clubs, diamonds, hearts.
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.selectGame(const Diamonds());
      n.updateInput('tricks', [3, 4, 4, 2]);
      n.deselectGame();
      n.selectGame(const Hearts());
      n.updateInput('tricks', [2, 3, 4, 4]);
      n.deselectGame();
      expect(
        c.read(calculatorProvider).history.map((r) => r.game.id).toList(),
        ['clubs', 'diamonds', 'hearts'],
      );
      // Move third to first position.
      n.reorderRounds(2, 0);
      final s = c.read(calculatorProvider);
      expect(s.history.map((r) => r.game.id).toList(), [
        'hearts',
        'clubs',
        'diamonds',
      ]);
      expect(s.history.map((r) => r.roundNumber).toList(), [1, 2, 3]);
    });
  });

  group('Edit-existing-round flow', () {
    test(
      'restoreRound trims subsequent rounds, then deselectGame re-appends',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput('tricks', [4, 4, 2, 3]);
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput('tricks', [4, 3, 5, 1]);
        n.deselectGame();

        final clubsRound = c.read(calculatorProvider).history.first;
        n.restoreRound(clubsRound);
        var s = c.read(calculatorProvider);
        expect(s.isEditingExistingRound, isTrue);
        expect(s.history.length, 0); // duck round was trimmed too
        expect(s.selectedGame!.id, 'clubs');

        // Make a tweak and finish edit.
        n.updateInput('tricks', [3, 4, 3, 3]);
        n.deselectGame();

        s = c.read(calculatorProvider);
        expect(s.isEditingExistingRound, isFalse);
        expect(s.history.length, 2); // both rounds restored
        expect(s.history[0].game.id, 'clubs');
        expect(s.history[1].game.id, 'duck');
      },
    );

    test('cancelEditRound restores the snapshot exactly', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();

      final beforeEdit = c.read(calculatorProvider);
      n.restoreRound(beforeEdit.history.first);
      n.updateInput('tricks', [13, 0, 0, 0]); // change input
      n.cancelEditRound();

      final after = c.read(calculatorProvider);
      expect(after.isEditingExistingRound, isFalse);
      expect(after.history.length, 1);
      expect(after.history.first.input['tricks'], [4, 4, 2, 3]);
    });

    test('hasActiveChanges is false when nothing was changed during edit', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.restoreRound(c.read(calculatorProvider).history.first);
      expect(c.read(calculatorProvider).hasActiveChanges, isFalse);
    });

    test('hasActiveChanges is true after modifying input during edit', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.restoreRound(c.read(calculatorProvider).history.first);
      n.updateInput('tricks', [5, 4, 2, 2]);
      expect(c.read(calculatorProvider).hasActiveChanges, isTrue);
    });
  });

  group('initSession / buildSession / loadSession', () {
    test('buildSession returns null before initSession', () {
      final c = makeContainer();
      expect(c.read(calculatorProvider.notifier).buildSession(), isNull);
    });

    test('initSession assigns id and timestamps', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.initSession();
      final s = c.read(calculatorProvider);
      expect(s.sessionId, isNotEmpty);
      expect(s.createdAt, isNotNull);
      expect(s.updatedAt, isNotNull);
    });

    test('buildSession reflects history and pending game', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      n.setDealer(0);
      n.initSession();
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      // Start a pending game.
      n.selectGame(const Duck());
      n.updateInput('tricks', [3, 0, 0, 0]);
      n.deselectGame();

      final session = n.buildSession()!;
      expect(session.playerNames, ['A', 'B', 'C', 'D']);
      expect(session.rounds.length, 1);
      expect(session.rounds.first.gameId, 'clubs');
      expect(session.pendingRound, isNotNull);
      expect(session.pendingRound!.gameId, 'duck');
      expect(session.pendingRound!.input['tricks'], [3, 0, 0, 0]);
    });

    test('loadSession restores history and pending game', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      n.setDealer(0);
      n.initSession();
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput('tricks', [3, 0, 0, 0]);
      n.deselectGame();

      final session = n.buildSession()!;

      // Reset and load it back.
      n.reset();
      expect(c.read(calculatorProvider).playerNames, ['', '', '', '']);
      n.loadSession(session);

      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['A', 'B', 'C', 'D']);
      expect(s.history.length, 1);
      expect(s.history.first.game.id, 'clubs');
      expect(s.hasPendingGame, isTrue);
      expect(s.pendingGame!.id, 'duck');
      expect(s.pendingInput['tricks'], [3, 0, 0, 0]);
    });
  });

  group('reset', () {
    test('reset clears all session state', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setDealer(0);
      n.initSession();
      n.reset();
      final s = c.read(calculatorProvider);
      expect(s.sessionId, '');
      expect(s.dealerChosen, isFalse);
      expect(s.playerNames, ['', '', '', '']);
      expect(s.history, isEmpty);
    });
  });

  group('isInputValid edge cases', () {
    test(
      'negative count is currently considered valid as long as the sum matches',
      () {
        // Locks in current behavior of CountsInputDescriptor validation:
        // it only checks the sum equals total, not that each entry is >= 0.
        // [-1, 14, 0, 0] sums to 13 → isInputValid is true today.
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.selectGame(const Clubs());
        n.updateInput('tricks', [-1, 14, 0, 0]);
        expect(c.read(calculatorProvider).isInputValid, isTrue);
      },
    );
  });

  group('reorderRounds — additional coverage', () {
    test('preserves each historical record\'s dealerIndex', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.selectGame(const Diamonds());
      n.updateInput('tricks', [3, 4, 4, 2]);
      n.deselectGame();
      n.selectGame(const Hearts());
      n.updateInput('tricks', [2, 3, 4, 4]);
      n.deselectGame();

      final dealersBefore = c
          .read(calculatorProvider)
          .history
          .map((r) => r.dealerIndex)
          .toList();
      expect(dealersBefore, [0, 1, 2]);
      final dealerStateBefore = c.read(calculatorProvider).dealerIndex;

      n.reorderRounds(2, 0);

      final s = c.read(calculatorProvider);
      // Each round's recorded dealerIndex follows it (no rewriting).
      expect(s.history.map((r) => r.dealerIndex).toList(), [2, 0, 1]);
      // The "next round" dealerIndex stored on state is not changed by a
      // reorder — locks in current behavior.
      expect(s.dealerIndex, dealerStateBefore);
    });

    test('no-op when oldIndex == newIndex (history unchanged, no crash)', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0);
      n.selectGame(const Clubs());
      n.updateInput('tricks', [4, 4, 2, 3]);
      n.deselectGame();
      n.selectGame(const Duck());
      n.updateInput('tricks', [4, 3, 5, 1]);
      n.deselectGame();

      final before = c
          .read(calculatorProvider)
          .history
          .map((r) => r.game.id)
          .toList();
      n.reorderRounds(1, 1);
      final after = c
          .read(calculatorProvider)
          .history
          .map((r) => r.game.id)
          .toList();
      expect(after, before);
    });
  });

  group('Edit-existing-round flow — additional coverage', () {
    test(
      'edit last round + save with no changes leaves dealer/round/history unchanged',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput('tricks', [4, 4, 2, 3]);
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput('tricks', [4, 3, 5, 1]);
        n.deselectGame();

        final before = c.read(calculatorProvider);
        final dealerBefore = before.dealerIndex;
        final roundBefore = before.roundNumber;
        final lenBefore = before.history.length;

        // Restore the LAST round (round 2 = duck) and save without changes.
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
        n.setPlayerName(0, 'A');
        n.setPlayerName(1, 'B');
        n.setPlayerName(2, 'C');
        n.setPlayerName(3, 'D');
        n.setDealer(0);
        n.initSession();
        // 2 rounds: round 1 dealer 0, round 2 dealer 1.
        n.selectGame(const Clubs());
        n.updateInput('tricks', [4, 4, 2, 3]);
        n.deselectGame();
        n.selectGame(const Duck());
        n.updateInput('tricks', [4, 3, 5, 1]);
        n.deselectGame();

        final session = n.buildSession()!;
        expect(session.pendingRound, isNull);
        expect(session.rounds.last.dealerIndex, 1);

        n.reset();
        n.loadSession(session);
        final s = c.read(calculatorProvider);
        expect(s.dealerIndex, 2);
        expect(s.chooserIndex, 3);
        expect(s.roundNumber, 3);
        expect(s.pendingGame, isNull);
        expect(s.hasPendingGame, isFalse);
      },
    );
  });

  group('hasActiveChanges — chooser changes', () {
    test('chooser-only deviation from default returns true', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setDealer(0); // default chooser becomes 1 after selectGame
      n.selectGame(const Clubs());
      // Default chooser is (0+1)%4 = 1; change it.
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

  group('reorderPlayerNames — dealer recalculation', () {
    test('moving the dealer up keeps dealer pointing at same person', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      n.setDealer(2); // dealer = C
      n.reorderPlayerNames(2, 0);
      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['C', 'A', 'B', 'D']);
      expect(s.dealerIndex, 0); // C is still the dealer, now at index 0
    });

    test('with dealerChosen==false, dealerIndex is not moved', () {
      final c = makeContainer();
      final n = c.read(calculatorProvider.notifier);
      n.setPlayerName(0, 'A');
      n.setPlayerName(1, 'B');
      n.setPlayerName(2, 'C');
      n.setPlayerName(3, 'D');
      n.setDealer(2);
      n.clearDealer();
      n.reorderPlayerNames(2, 0);
      final s = c.read(calculatorProvider);
      expect(s.playerNames, ['C', 'A', 'B', 'D']);
      expect(s.dealerChosen, isFalse);
      // dealerIndex stays at the previously-set value.
      expect(s.dealerIndex, 2);
    });
  });

  group('hasMeaningfulPendingInput — single/dual player', () {
    test(
      'SinglePlayerInputDescriptor with a winner set is meaningful (loaded)',
      () {
        // Reaching this state via the live flow is impossible because setting
        // 'winner' makes isInputValid true and the round is then completed.
        // The pending state only exists when restored from a saved session.
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final session = GameSession(
          id: 's1',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          playerNames: const ['A', 'B', 'C', 'D'],
          rounds: const [],
          pendingRound: const PendingRound(
            gameId: 'kingOfHearts',
            gameName: 'Hartenheer',
            dealerIndex: 0,
            chooserIndex: 1,
            input: {'winner': 2},
          ),
        );
        n.loadSession(session);
        expect(c.read(calculatorProvider).hasMeaningfulPendingInput, isTrue);
      },
    );

    test(
      'DualPlayerInputDescriptor with only one slot set is meaningful (loaded)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        final session = GameSession(
          id: 's1',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          playerNames: const ['A', 'B', 'C', 'D'],
          rounds: const [],
          pendingRound: const PendingRound(
            gameId: 'seventhAndThirteenth',
            gameName: '7e / 13e',
            dealerIndex: 0,
            chooserIndex: 1,
            input: {'trick13winner': 2},
          ),
        );
        n.loadSession(session);
        expect(c.read(calculatorProvider).hasMeaningfulPendingInput, isTrue);
      },
    );
  });

  group('deleteLastRound while pending game present', () {
    test(
      'deleting last round keeps the pending game intact (current behavior)',
      () {
        final c = makeContainer();
        final n = c.read(calculatorProvider.notifier);
        n.setDealer(0);
        n.selectGame(const Clubs());
        n.updateInput('tricks', [4, 4, 2, 3]);
        n.deselectGame();
        // Start a pending game.
        n.selectGame(const Duck());
        n.updateInput('tricks', [3, 0, 0, 0]);
        n.deselectGame();
        expect(c.read(calculatorProvider).hasPendingGame, isTrue);

        n.deleteLastRound();
        final s = c.read(calculatorProvider);
        expect(s.history, isEmpty);
        // Pending game survives the delete operation.
        expect(s.hasPendingGame, isTrue);
        expect(s.pendingGame!.id, 'duck');
      },
    );
  });
}
