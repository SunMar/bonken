import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/state/calculator_provider.dart';

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

    test('setDealer marks dealerChosen and resets round/history', () {
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
}
