import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/double_matrix.dart';
import '../models/game_mechanics.dart';
import '../models/game_session.dart';
import '../models/games/game_catalog.dart';
import '../models/hearts_variant.dart';
import '../models/input_descriptor.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/round_record.dart';
import '../models/rule_variants.dart';
import '../models/score_result.dart';
import '../models/starter_variant.dart';

import 'game_history_provider.dart';

/// Describes how far along the current round's input is.
enum InputState { none, partial, complete }

/// Sealed type for the stashed-round slot. [NoPendingRound] means nothing is
/// stashed; [ActivePendingRound] holds the game, input, and doubles together
/// so the type system ensures all three are set or unset as a unit.
sealed class PendingRoundState {
  const PendingRoundState();
}

class NoPendingRound extends PendingRoundState {
  const NoPendingRound();
}

class ActivePendingRound extends PendingRoundState {
  const ActivePendingRound({
    required this.game,
    this.input,
    this.doubles = const DoubleMatrix(),
  });

  final MiniGame game;
  final GameInput? input;
  final DoubleMatrix doubles;
}

/// Sealed state for [calculatorProvider].
///
/// [NoSession] is the idle state — the notifier is alive but no game is in
/// progress. [ActiveSession] carries all transient round-by-round data.
sealed class CalculatorState {
  const CalculatorState();
}

/// Idle state: the notifier is alive but no game session is in progress.
class NoSession extends CalculatorState {
  const NoSession();
}

/// Active game session — carries all transient round-by-round state.
@immutable
class ActiveSession extends CalculatorState {
  factory ActiveSession({
    required String sessionId,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? scoredAt,
    required List<Player> players,
    required String firstDealerId,
    required String dealerId,
    required String chooserId,
    int roundNumber = 1,
    List<RoundRecord> history = const [],
    MiniGame? selectedGame,
    GameInput? input,
    DoubleMatrix doubles = const DoubleMatrix(),
    ScoreResult? result,
    PendingRoundState pending = const NoPendingRound(),
    ScoreResult? partialResult,
    int? editingRoundIndex,
    GameInput? editOriginalInput,
    DoubleMatrix? editOriginalDoubles,
    String? editOriginalChooserId,
    RuleVariants ruleVariants = const RuleVariants(),
    String? gameName,
  }) {
    return ActiveSession._(
      sessionId: sessionId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? createdAt,
      scoredAt: scoredAt ?? createdAt,
      players: players,
      playerNames: List.unmodifiable([for (final p in players) p.name]),
      firstDealerId: firstDealerId,
      displayedPlayers: rotatedFromDealer(players, firstDealerId),
      dealerId: dealerId,
      chooserId: chooserId,
      roundNumber: roundNumber,
      history: history,
      selectedGame: selectedGame,
      input: input,
      doubles: doubles,
      result: result,
      pending: pending,
      partialResult: partialResult,
      editingRoundIndex: editingRoundIndex,
      editOriginalInput: editOriginalInput,
      editOriginalDoubles: editOriginalDoubles,
      editOriginalChooserId: editOriginalChooserId,
      ruleVariants: ruleVariants,
      gameName: gameName,
    );
  }

  // Private constructor for copyWith — accepts pre-computed derived lists so
  // references are preserved when the underlying data hasn't changed, keeping
  // select() callbacks stable across unrelated state mutations.
  // ignore: prefer_const_constructors_in_immutables
  const ActiveSession._({
    required this.sessionId,
    required this.createdAt,
    required this.updatedAt,
    required this.scoredAt,
    required this.players,
    required this.playerNames,
    required this.firstDealerId,
    required this.displayedPlayers,
    required this.dealerId,
    required this.chooserId,
    required this.roundNumber,
    required this.history,
    required this.selectedGame,
    required this.input,
    required this.doubles,
    required this.result,
    required this.pending,
    required this.partialResult,
    required this.editingRoundIndex,
    required this.editOriginalInput,
    required this.editOriginalDoubles,
    required this.editOriginalChooserId,
    required this.ruleVariants,
    required this.gameName,
  });

  /// Unique ID for this game session.
  final String sessionId;

  /// When this session was started.
  final DateTime createdAt;

  /// Last time meaningful content was saved (completed round, player
  /// reorder, player/dealer name change). Not updated on load or on
  /// cancelled edits.
  final DateTime updatedAt;

  /// When scores last changed — advances only when a round is committed
  /// (appended, replaced, or deleted). Player/name/rule edits leave this
  /// unchanged. Starts at [createdAt] for new sessions.
  final DateTime scoredAt;

  /// Players in seat order. UUIDs are stable across renames and reorders.
  final List<Player> players;

  /// Player names in seat order. Stored (not computed) so selectors that
  /// watch this field get a stable reference when players haven't changed.
  final List<String> playerNames;

  /// The player ID of the dealer for round 1.
  /// Dealer for round N = players[(firstDealerIdx + N − 1) % playerCount].
  final String firstDealerId;

  /// Players in display order — starting from the round-1 dealer, rotating
  /// forward. Stored (not computed) so selectors watching this field get a
  /// stable reference when neither [players] nor [firstDealerId] have changed.
  final List<Player> displayedPlayers;

  /// Player ID of the dealer for the current/next round.
  final String dealerId;

  /// Player ID of the chooser for the current round.
  /// Defaults to the player left of the dealer but is manually selectable.
  final String chooserId;

  // ---------------------------------------------------------------------------
  // Computed seat-index getters — derived on demand from ID fields via the
  // shared throwing helper. These ID fields are always valid in an
  // ActiveSession (the factory requires them; storage loads pass through
  // _validateReferences), so seatIndexOf never throws here — a throw would
  // mean a programming bug, which is exactly what we want surfaced.
  // ---------------------------------------------------------------------------

  /// Seat index (0–3) of the current dealer.
  int get dealerIndex => seatIndexOf(players, dealerId);

  /// Seat index (0–3) of the current chooser.
  int get chooserIndex => seatIndexOf(players, chooserId);

  /// Seat index (0–3) of the round-1 dealer.
  int get firstDealerIndex => seatIndexOf(players, firstDealerId);

  /// Position of the chooser within [displayedPlayers] (0–3).
  int get displayedChooserIndex => seatIndexOf(displayedPlayers, chooserId);

  /// 1-based round counter, 1–12: the number of completed rounds + 1.
  /// Increments each time a scored game is confirmed; never reset by a
  /// dealer edit (`setDealer` recomputes the dealer from history length and
  /// leaves the round number untouched).
  final int roundNumber;

  /// All completed rounds in order.
  final List<RoundRecord> history;

  final MiniGame? selectedGame;

  /// Typed in-memory input for the current round; null when no game is selected.
  final GameInput? input;
  final DoubleMatrix doubles;
  final ScoreResult? result;

  /// Stashed round — [NoPendingRound] when nothing is stashed;
  /// [ActivePendingRound] when the user navigated away before finishing a
  /// round. The sealed type ensures game, input, and doubles are always set
  /// or unset as a unit.
  final PendingRoundState pending;

  /// Whether there is a partially-entered game that was interrupted.
  bool get hasPendingGame => pending is ActivePendingRound && result == null;

  /// Whether the stashed pending round belongs to the game currently in the
  /// live slot. Parallels [hasPendingGame] but keys on [selectedGame], and
  /// deliberately omits the `result == null` clause — callers needing that
  /// check it themselves.
  bool get hasPendingForSelectedGame {
    final p = pending;
    return p is ActivePendingRound && selectedGame?.id == p.game.id;
  }

  /// True when the pending (interrupted) game has meaningful input — i.e. the
  /// user actually entered something beyond the defaults (scores or doubles).
  bool get hasMeaningfulPendingInput {
    final p = pending;
    if (p is! ActivePendingRound) return false;
    if (p.doubles.hasAnyDouble) return true;
    final gameInput = p.input;
    if (gameInput == null) return false;
    return !p.game.inputDescriptor.isEmpty(gameInput);
  }

  /// Intermediate score shown while the round is partway entered (see
  /// [InputState.partial]): for [CountsInputDescriptor] games when the sum is
  /// > 0 but < [CountsInputDescriptor.total], and for the two-slot 7e/13e
  /// recipient game when exactly one slot is filled. Null for single-slot
  /// recipient games, which are only ever empty or complete.
  final ScoreResult? partialResult;

  /// Non-null when the user is re-editing an already-scored round; holds the
  /// 0-based index into [history] of the round being edited.
  final int? editingRoundIndex;

  /// True when the user is re-editing a round that was already scored.
  bool get isEditingExistingRound => editingRoundIndex != null;

  /// Original input/doubles/chooser captured at the start of an edit, used to
  /// detect whether anything actually changed (see [hasActiveChanges]).
  final GameInput? editOriginalInput;
  final DoubleMatrix? editOriginalDoubles;
  final String? editOriginalChooserId;

  /// The per-game rule variants (starter + hearts) in effect for this session.
  final RuleVariants ruleVariants;

  /// Optional user-supplied name for this game session. Never the empty string.
  final String? gameName;

  /// Seat index (0–3) of the player who leads the first trick.
  int get starterIndex =>
      starterIndexFor(chooserIndex, ruleVariants.starterVariant);

  /// True when there is meaningful active input that would be lost on cancel.
  bool get hasActiveChanges {
    if (selectedGame == null) return false;
    if (isEditingExistingRound) {
      final origInput = editOriginalInput;
      final origDoubles = editOriginalDoubles;
      final origChooser = editOriginalChooserId;
      if (origInput == null || origDoubles == null || origChooser == null) {
        return true; // safety fallback
      }
      if (chooserId != origChooser) return true;
      if (doubles != origDoubles) return true;
      if (input != origInput) return true;
      return false;
    }
    final game = selectedGame!;
    final gameInput = input;
    if (gameInput != null && !game.inputDescriptor.isEmpty(gameInput)) {
      return true;
    }
    if (doubles.hasAnyDouble) return true;
    if (chooserId != players[chooserIndexFor(dealerIndex)].id) return true;
    return false;
  }

  InputState get inputState {
    final game = selectedGame;
    if (game == null) return InputState.none;
    final gameInput = input;
    if (gameInput == null) return InputState.none;
    if (game.inputDescriptor.isComplete(gameInput)) return InputState.complete;
    if (game.inputDescriptor.isEmpty(gameInput)) return InputState.none;
    return InputState.partial;
  }

  ActiveSession copyWith({
    String? sessionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? scoredAt,
    List<Player>? players,
    String? firstDealerId,
    String? dealerId,
    String? chooserId,
    int? roundNumber,
    List<RoundRecord>? history,
    MiniGame? selectedGame,
    bool clearSelectedGame = false,
    GameInput? input,
    bool clearInput = false,
    DoubleMatrix? doubles,
    ScoreResult? result,
    bool clearResult = false,
    PendingRoundState? pending,
    ScoreResult? partialResult,
    bool clearPartialResult = false,
    int? editingRoundIndex,
    GameInput? editOriginalInput,
    DoubleMatrix? editOriginalDoubles,
    String? editOriginalChooserId,
    bool clearEditState = false,
    RuleVariants? ruleVariants,
    String? gameName,
    bool clearGameName = false,
  }) {
    final newPlayers = players ?? this.players;
    final newFirstDealerId = firstDealerId ?? this.firstDealerId;
    // Preserve stable references when the underlying data hasn't changed so
    // that select() callbacks watching these fields don't fire unnecessarily.
    final newPlayerNames = players != null
        ? List<String>.unmodifiable([for (final p in newPlayers) p.name])
        : playerNames;
    final newDisplayedPlayers = (players != null || firstDealerId != null)
        ? rotatedFromDealer(newPlayers, newFirstDealerId)
        : displayedPlayers;
    return ActiveSession._(
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scoredAt: scoredAt ?? this.scoredAt,
      players: newPlayers,
      playerNames: newPlayerNames,
      firstDealerId: newFirstDealerId,
      displayedPlayers: newDisplayedPlayers,
      dealerId: dealerId ?? this.dealerId,
      chooserId: chooserId ?? this.chooserId,
      roundNumber: roundNumber ?? this.roundNumber,
      history: history ?? this.history,
      selectedGame: clearSelectedGame
          ? null
          : (selectedGame ?? this.selectedGame),
      input: clearInput ? null : (input ?? this.input),
      doubles: doubles ?? this.doubles,
      result: clearResult ? null : (result ?? this.result),
      pending: pending ?? this.pending,
      partialResult: clearPartialResult
          ? null
          : (partialResult ?? this.partialResult),
      editingRoundIndex: clearEditState
          ? null
          : (editingRoundIndex ?? this.editingRoundIndex),
      editOriginalInput: clearEditState
          ? null
          : (editOriginalInput ?? this.editOriginalInput),
      editOriginalDoubles: clearEditState
          ? null
          : (editOriginalDoubles ?? this.editOriginalDoubles),
      editOriginalChooserId: clearEditState
          ? null
          : (editOriginalChooserId ?? this.editOriginalChooserId),
      ruleVariants: ruleVariants ?? this.ruleVariants,
      gameName: clearGameName ? null : (gameName ?? this.gameName),
    );
  }
}

class CalculatorNotifier extends Notifier<CalculatorState> {
  @override
  CalculatorState build() {
    // Cache before onDispose so the closure doesn't call ref.read while the
    // element is torn down. gameHistoryProvider is not autoDispose, so its
    // notifier outlives this one and saveGame stays valid.
    final historyNotifier = ref.read(gameHistoryProvider.notifier);
    _autosave = _AutosaveCoordinator(historyNotifier.saveGame);
    ref.onDispose(() {
      // Riverpod 3.3 forbids reading `state` in onDispose, so flush the
      // coordinator's pre-built snapshot instead. Future.microtask defers
      // saveGame() past the onDispose frame so Riverpod's _debugCallbackStack
      // is back to 0 before GameHistoryNotifier.future calls
      // _throwIfInvalidUsage().
      final session = _autosave.takePending();
      if (session == null) return;
      unawaited(
        Future.microtask(
          () => historyNotifier.saveGame(session),
        ).catchError((_) {}),
      );
    });
    return const NoSession();
  }

  /// Owns the debounced autosave — the timer, the latest snapshot, and the
  /// single in-flight write. Assigned once in [build]. See
  /// [_AutosaveCoordinator] for the debounce/flush/race-safety contract.
  late _AutosaveCoordinator _autosave;

  /// The active session. **Throws** if the state is [NoSession] — use only on
  /// paths where an active session is a precondition. Idle-tolerant paths (e.g.
  /// [buildSession], [_flushOutgoingSession]) must use an explicit
  /// `state is ActiveSession` guard instead.
  ActiveSession get _session => state as ActiveSession;

  @override
  set state(CalculatorState newState) {
    super.state = newState;
    // The snapshot must be built here (not in onDispose, which can't read
    // `state`). Only active sessions are persisted; NoSession transitions are
    // cleared by their callers (reset / cancelPendingAutosave).
    if (newState is ActiveSession) _autosave.schedule(buildSession()!);
  }

  /// Flushes the outgoing session's pending autosave before it is replaced by a
  /// switch to [incomingId] (a new game or a different loaded session).
  /// Re-loading the *same* session leaves its pending autosave armed.
  void _flushOutgoingSession({String? incomingId}) {
    final s = state;
    if (s is! ActiveSession) return;
    if (incomingId != null && s.sessionId == incomingId) return;
    _autosave.flush();
  }

  void setPlayerName(int index, String name) {
    final updated = List<Player>.from(_session.players);
    updated[index] = updated[index].copyWith(name: name);
    state = _session.copyWith(players: updated, updatedAt: DateTime.now());
  }

  /// Atomically applies a full player reorder + name updates + dealer change.
  /// Called by EditGameScreen so that player UUIDs stay bound to the
  /// correct seat after a drag-reorder.
  ///
  /// [firstDealerIdx] is the seat index of the player who dealt round 1.
  /// The current-round dealer is derived from that via the rotation formula.
  void setPlayersAndDealer(List<Player> players, int firstDealerIdx) {
    final nextDealerIdx =
        (firstDealerIdx + _session.history.length) % playerCount;
    state = _session.copyWith(
      players: players,
      firstDealerId: players[firstDealerIdx].id,
      dealerId: players[nextDealerIdx].id,
      updatedAt: DateTime.now(),
    );
  }

  void setDealer(int index) {
    // Back-compute firstDealerId so the next round's dealer is players[index].
    final n = _session.history.length;
    final firstDealerIdx =
        ((index - n) % playerCount + playerCount) % playerCount;
    state = _session.copyWith(
      firstDealerId: _session.players[firstDealerIdx].id,
      dealerId: _session.players[index].id,
    );
  }

  void setChooser(int index) {
    state = _session.copyWith(chooserId: _session.players[index].id);
    _recalculate();
  }

  void selectGame(MiniGame game) {
    // If we're resuming the same game that was interrupted, restore partial input.
    final s = _session;
    final p = s.pending;
    if (p is ActivePendingRound && p.game.id == game.id && s.result == null) {
      state = s.copyWith(
        selectedGame: game,
        input: p.input,
        doubles: p.doubles,
      );
      _recalculate();
      return;
    }

    final defaults = game.inputDescriptor.defaults(s.players);

    state = s.copyWith(
      selectedGame: game,
      chooserId: s.players[chooserIndexFor(s.dealerIndex)].id,
      input: defaults,
      doubles: const DoubleMatrix(),
      clearResult: true,
      clearPartialResult: true,
      pending: ActivePendingRound(game: game, input: defaults),
    );
  }

  /// Shared exit path used by [deselectGame], [discardGame], [exitPendingSlot],
  /// [deleteLastRound] and [cancelEditRound]. Clears every slot/edit field, then
  /// derives `dealerId`, `roundNumber` and `chooserId` from [newHistory] and
  /// [ActiveSession.firstDealerId].
  ActiveSession _exitSlot(
    ActiveSession s, {
    required List<RoundRecord> newHistory,
    bool historyChanged = false,
    PendingRoundState? overridePending,
  }) {
    // Next dealer is always derived from the initial dealer + completed rounds,
    // so this remains correct whether we're cancelling an edit of an older
    // round, deleting a round, or completing a new one.
    final nextDealerIdx =
        (s.firstDealerIndex + newHistory.length) % playerCount;
    final nextDealerId = s.players[nextDealerIdx].id;
    final nextChooserIdx = chooserIndexFor(nextDealerIdx);
    final nextRound = newHistory.length + 1;
    return s.copyWith(
      history: newHistory,
      dealerId: nextDealerId,
      roundNumber: nextRound,
      chooserId: (overridePending ?? s.pending) is ActivePendingRound
          ? s.chooserId
          : s.players[nextChooserIdx].id,
      clearSelectedGame: true,
      clearInput: true,
      doubles: const DoubleMatrix(),
      clearResult: true,
      clearPartialResult: true,
      clearEditState: true,
      updatedAt: historyChanged ? DateTime.now() : s.updatedAt,
      scoredAt: historyChanged ? DateTime.now() : s.scoredAt,
      pending:
          overridePending, // null → preserve s.pending; non-null → override
    );
  }

  /// Builds a [RoundRecord] from the current slot (selected game + result +
  /// input + doubles + chooser), tagged with [roundNumber]. The two history-
  /// committing branches of [deselectGame] differ only in that number.
  RoundRecord _recordFromSlot(ActiveSession s, {required int roundNumber}) =>
      RoundRecord(
        roundNumber: roundNumber,
        game: s.selectedGame!,
        chooserId: s.chooserId,
        scoresByPlayer: Map<String, int>.from(s.result!.scores),
        input: s.input!,
        doubles: s.doubles,
      );

  /// Leaves the input slot.
  ///
  /// Four cases, in order:
  ///   1. Editing an existing round, slot has a valid result: replace the round.
  ///   2. Editing, slot incomplete: falls back to cancel.
  ///   3. New round, result present: append to history, advance dealer/round.
  ///   4. New round, no result but has a selected game: stash as pending.
  void deselectGame() {
    final s = _session;
    final editIndex = s.editingRoundIndex;

    if (editIndex != null) {
      if (s.result == null) {
        cancelEditRound();
        return;
      }
      final replacement = _recordFromSlot(
        s,
        roundNumber: s.history[editIndex].roundNumber,
      );
      final newHistory = [
        ...s.history.sublist(0, editIndex),
        replacement,
        ...s.history.sublist(editIndex + 1),
      ];
      state = _exitSlot(s, newHistory: newHistory, historyChanged: true);
      return;
    }

    if (s.result != null) {
      // New round, completed: append and clear the pending stash.
      final appended = [
        ...s.history,
        _recordFromSlot(s, roundNumber: s.roundNumber),
      ];
      state = _exitSlot(
        s,
        newHistory: appended,
        historyChanged: true,
        overridePending: const NoPendingRound(),
      );
      return;
    }

    if (s.selectedGame != null) {
      // Pending round, incomplete: pending.input is already synced via
      // write-through in updateInput/updateDoubles, so just exit the slot.
      state = _exitSlot(s, newHistory: s.history, overridePending: s.pending);
      return;
    }

    state = _exitSlot(s, newHistory: s.history);
  }

  /// Discards the in-progress input and returns to game selection.
  /// When editing a pending round, also clears the [ActivePendingRound] so
  /// the user can switch to a different game. When editing a completed round
  /// (via [restoreRound]), the history is left unchanged.
  void discardGame() {
    final s = _session;
    state = _exitSlot(
      s,
      newHistory: s.history,
      overridePending: s.hasPendingForSelectedGame
          ? const NoPendingRound()
          : null,
    );
  }

  /// Exits the live slot without saving or discarding the pending round.
  /// Used by the back button when editing a pending round. [updateInput] and
  /// [updateDoubles] already write through to [ActivePendingRound], so the
  /// stash is always current and no extra copy is needed here.
  void exitPendingSlot() {
    final s = _session;
    state = _exitSlot(s, newHistory: s.history, overridePending: s.pending);
  }

  /// Deletes the last completed round from history, rolling dealer/round back.
  ///
  /// [roundNumber] identifies the round the caller means to delete. If the last
  /// round no longer matches it — e.g. another round was committed while the
  /// delete-confirm dialog was open — this no-ops rather than silently deleting
  /// a *different* round than the one the user confirmed.
  void deleteLastRound(int roundNumber) {
    final s = _session;
    if (s.history.isEmpty || s.history.last.roundNumber != roundNumber) return;
    final newHistory = s.history.sublist(0, s.history.length - 1);
    state = _exitSlot(s, newHistory: newHistory, historyChanged: true);
  }

  void updateInput(GameInput input) {
    final s = _session;
    if (s.input == input) return;
    final p = s.pending;
    state = p is ActivePendingRound && s.selectedGame?.id == p.game.id
        ? s.copyWith(
            input: input,
            pending: ActivePendingRound(
              game: p.game,
              input: input,
              doubles: p.doubles,
            ),
          )
        : s.copyWith(input: input);
    _recalculate();
  }

  void updateDoubles(DoubleMatrix doubles) {
    final s = _session;
    if (s.doubles == doubles) return;
    final p = s.pending;
    state = p is ActivePendingRound && s.selectedGame?.id == p.game.id
        ? s.copyWith(
            doubles: doubles,
            pending: ActivePendingRound(
              game: p.game,
              input: p.input,
              doubles: doubles,
            ),
          )
        : s.copyWith(doubles: doubles);
    _recalculate();
  }

  /// Restores a past round for re-editing. Loads the round's data into the
  /// input slot and tags [ActiveSession.editingRoundIndex] with its position
  /// in [history]; the history list itself is left untouched.
  void restoreRound(RoundRecord record) {
    final s = _session;
    final index = s.history.indexWhere(
      (r) => r.roundNumber == record.roundNumber,
    );
    assert(index >= 0, 'restoreRound: record not found in history');
    if (index < 0) return;
    final chooserIdx = seatIndexOf(s.players, record.chooserId);
    final dealerIdx = dealerIndexFor(chooserIdx);
    state = s.copyWith(
      dealerId: s.players[dealerIdx].id,
      chooserId: record.chooserId,
      roundNumber: record.roundNumber,
      selectedGame: record.game,
      input: record.input,
      doubles: record.doubles,
      result: ScoreResult(scores: Map<String, int>.from(record.scoresByPlayer)),
      clearPartialResult: true,
      editingRoundIndex: index,
      editOriginalInput: record.input.copy(),
      editOriginalDoubles: record.doubles,
      editOriginalChooserId: record.chooserId,
    );
  }

  /// Cancels an in-progress edit. Because [history] was never mutated during
  /// the edit, this just clears the slot and recomputes from history.
  void cancelEditRound() {
    final s = _session;
    if (s.editingRoundIndex == null) return;
    state = _exitSlot(s, newHistory: s.history);
  }

  /// Recalculates the result whenever the state changes, or clears it if input
  /// is no longer valid. Skips emitting when the result is unchanged.
  void _recalculate() {
    final s = _session;
    final game = s.selectedGame;
    if (game == null) return;

    if (s.inputState == InputState.none) {
      if (s.result != null || s.partialResult != null) {
        state = s.copyWith(clearResult: true, clearPartialResult: true);
      }
      return;
    }

    // Both the complete and partial branches score the same way; only which
    // slot it lands in (and the complete-only sum assert) differs.
    final score = game.calculateScores(
      input: s.input!,
      doubles: s.doubles,
      players: s.players,
    );
    if (s.inputState == InputState.complete) {
      assert(
        score.scores.values.fold(0, (a, b) => a + b) == game.totalPoints,
        'Score sum mismatch for ${game.id}: '
        'got ${score.scores.values.fold(0, (a, b) => a + b)}, '
        'expected ${game.totalPoints}',
      );
      if (s.result == score && s.partialResult == null) return;
      state = s.copyWith(result: score, clearPartialResult: true);
    } else {
      if (s.partialResult == score && s.result == null) return;
      state = s.copyWith(clearResult: true, partialResult: score);
    }
  }

  void reset() {
    _autosave.cancel();
    state = const NoSession();
  }

  /// Cancels a pending debounced autosave **and awaits any already-in-flight
  /// write** before returning, then drops the snapshot. Callers about to mutate
  /// game history (delete, import-replace) must `await` this: a debounce timer
  /// that already fired leaves a `saveGame` suspended mid-write, and without the
  /// join it would resume *after* the delete and re-upsert the removed session
  /// (the resurrection race). Awaiting forces save-then-delete ordering, so the
  /// final state is correctly deleted.
  Future<void> cancelPendingAutosave() => _autosave.cancelAndJoin();

  /// Starts a brand-new game session: resets all transient state, applies the
  /// given [players] and [dealerIndex], and assigns a fresh session ID.
  void startNewGame({
    required List<Player> players,
    required int dealerIndex,
    RuleVariants ruleVariants = const RuleVariants(),
    String? gameName,
  }) {
    _flushOutgoingSession();
    final now = DateTime.now();
    state = ActiveSession(
      sessionId: const Uuid().v4(),
      createdAt: now,
      scoredAt: now,
      players: List<Player>.from(players),
      firstDealerId: players[dealerIndex].id,
      dealerId: players[dealerIndex].id,
      chooserId: players[chooserIndexFor(dealerIndex)].id,
      ruleVariants: ruleVariants,
      gameName: gameName,
    );
  }

  /// Builds a [GameSession] from the current state.
  ///
  /// Returns `null` when there is no active session — i.e. before
  /// [startNewGame] or [loadSession] has been called.
  GameSession? buildSession() {
    final s = state;
    if (s is! ActiveSession) return null;

    PendingRound? pendingRound;
    final p = s.pending;
    if (p is ActivePendingRound) {
      pendingRound = PendingRound(
        gameId: p.game.id,
        chooserId: s.chooserId,
        input: p.input,
        doubles: p.doubles.hasAnyDouble ? p.doubles : null,
      );
    }

    return GameSession(
      id: s.sessionId,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      scoredAt: s.scoredAt,
      players: s.players,
      firstDealerId: s.firstDealerId,
      ruleVariants: s.ruleVariants,
      pendingRound: pendingRound,
      rounds: s.history,
      gameName: s.gameName,
    );
  }

  /// Restores a previously saved [GameSession] into the current state.
  void loadSession(GameSession session) {
    _flushOutgoingSession(incomingId: session.id);

    final players = session.players;
    final initialDealerIdx = seatIndexOf(players, session.firstDealerId);

    final history = session.rounds;

    final nextDealerIdx = (initialDealerIdx + history.length) % playerCount;
    final nextRound = history.length + 1;

    PendingRoundState pendingState = const NoPendingRound();
    String chooserId = players[chooserIndexFor(nextDealerIdx)].id;
    String dealerId = players[nextDealerIdx].id;

    final savedPending = session.pendingRound;
    if (savedPending != null) {
      // gameById throws on an unknown id — fail loud rather than silently
      // dropping the stash to "no pending" (matches the error-throwing-lookup
      // convention; on a real load the id is already validated by
      // PendingRound.fromJson, so this is also a defensive consistency guard).
      final pendingDoubles = savedPending.doubles ?? const DoubleMatrix();
      pendingState = ActivePendingRound(
        game: gameById(savedPending.gameId),
        input: savedPending.input,
        doubles: pendingDoubles,
      );
      chooserId = savedPending.chooserId;
      // Derive dealer from chooser per game rules. chooserId is guaranteed
      // in players by _validateReferences at load time.
      final chooserIdx = seatIndexOf(players, savedPending.chooserId);
      dealerId = players[dealerIndexFor(chooserIdx)].id;
    }

    state = ActiveSession(
      sessionId: session.id,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      scoredAt: session.scoredAt,
      players: players,
      firstDealerId: session.firstDealerId,
      dealerId: dealerId,
      chooserId: chooserId,
      roundNumber: nextRound,
      history: history,
      pending: pendingState,
      ruleVariants: session.ruleVariants,
      gameName: session.gameName,
    );
  }

  /// Updates the [StarterVariant] for the current session.
  void setStarterVariant(StarterVariant variant) {
    state = _session.copyWith(
      ruleVariants: _session.ruleVariants.copyWith(starterVariant: variant),
      updatedAt: DateTime.now(),
    );
  }

  /// Updates the [HeartsVariant] for the current session.
  void setHeartsVariant(HeartsVariant variant) {
    state = _session.copyWith(
      ruleVariants: _session.ruleVariants.copyWith(heartsVariant: variant),
      updatedAt: DateTime.now(),
    );
  }

  /// Sets or clears the custom name for the current session.
  /// Pass null to remove the name.
  void setGameName(String? name) {
    state = _session.copyWith(
      gameName: name,
      clearGameName: name == null,
      updatedAt: DateTime.now(),
    );
  }
}

/// Owns the debounced "snapshot → persist" autosave for [CalculatorNotifier]:
/// the debounce timer, the latest pre-built snapshot, and the single in-flight
/// write. Collapsing this into one object replaces the three hand-written flush
/// copies the notifier used to carry, gives the snapshot a single owner, and —
/// crucially — lets a delete/import await any in-flight write so it can't be
/// overtaken (designs out the resurrection race).
///
/// Invariant: at most one write is "in flight" ([_inFlight]); the timer and the
/// pending snapshot are only ever touched here, so the mutual exclusion the old
/// `_autosaveTimer == null` guard relied on is structural rather than implicit.
class _AutosaveCoordinator {
  _AutosaveCoordinator(this._save);

  /// Persists a snapshot. Supplied by the owner (wraps
  /// `GameHistoryNotifier.saveGame`) so this coordinator stays free of Riverpod.
  final Future<void> Function(GameSession session) _save;

  /// Debounce window: coalesce bursts of mutations (counts stepper, chip taps)
  /// into one SharedPreferences write instead of re-encoding on every keystroke.
  static const _debounce = Duration(milliseconds: 400);

  Timer? _timer;
  GameSession? _pending;
  Future<void>? _inFlight;

  /// (Re)arms the debounce timer with the newest [snapshot].
  void schedule(GameSession snapshot) {
    _timer?.cancel();
    _pending = snapshot;
    _timer = Timer(_debounce, () {
      final session = takePending();
      if (session != null) _run(session);
    });
  }

  /// Cancels the debounce timer and returns the not-yet-written snapshot (if
  /// any), clearing it. Does **not** write — the caller decides how (onDispose
  /// defers via microtask to dodge the Riverpod dispose-frame constraint).
  GameSession? takePending() {
    _timer?.cancel();
    _timer = null;
    final session = _pending;
    _pending = null;
    return session;
  }

  /// Writes the pending snapshot immediately (used when switching sessions).
  /// No-op when nothing is pending.
  void flush() {
    final session = takePending();
    if (session != null) _run(session);
  }

  /// Drops the pending snapshot and timer without writing (reset path).
  void cancel() => takePending();

  /// Cancels a pending autosave and awaits any already-in-flight write, so a
  /// delete/replace that runs next removes whatever was just written rather
  /// than being overtaken by it.
  Future<void> cancelAndJoin() async {
    takePending();
    await _inFlight;
  }

  void _run(GameSession session) {
    // Best-effort background write; in-memory state is intact and the next
    // mutation re-triggers an autosave. Track the future so cancelAndJoin can
    // await it; clear the handle when it settles unless a newer write replaced
    // it.
    final future = _save(session).catchError((_) {});
    _inFlight = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_inFlight, future)) _inFlight = null;
      }),
    );
  }
}

final calculatorProvider =
    NotifierProvider.autoDispose<CalculatorNotifier, CalculatorState>(
      CalculatorNotifier.new,
    );

/// Narrows [calculatorProvider] to its [ActiveSession] state for the
/// session-bound screens (GameScreen, RoundInputScreen, EditGameScreen), which
/// only ever run while a game is in progress. They watch
/// `activeSessionProvider.select(...)` instead of casting `state as
/// ActiveSession` in every callback — the cast lives here, in one place.
///
/// `autoDispose` is deliberate: the provider is alive only while a screen is
/// watching it. When the user leaves the game (back to Home), the last listener
/// drops, this provider is torn down, and its own subscription to
/// [calculatorProvider] goes with it — so the subsequent `NoSession` transition
/// (see `GameScreen.dispose`) never re-runs the cast on a [NoSession] value. A
/// plain `Provider` would keep that subscription and throw on the flip.
final activeSessionProvider = Provider.autoDispose<ActiveSession>(
  (ref) => ref.watch(calculatorProvider) as ActiveSession,
);
