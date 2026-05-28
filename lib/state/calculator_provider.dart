import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/double_matrix.dart';
import '../models/game_mechanics.dart';
import '../models/game_session.dart';
import '../models/games/game_catalog.dart';
import '../models/input_descriptor.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/round_record.dart';
import '../models/score_result.dart';

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

/// Holds the transient state for the score calculator screen.
@immutable
class CalculatorState {
  factory CalculatorState({
    String sessionId = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Player>? players,
    String firstDealerId = '',
    String dealerId = '',
    String chooserId = '',
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
  }) {
    final resolvedPlayers =
        players ??
        [
          Player(name: ''),
          Player(name: ''),
          Player(name: ''),
          Player(name: ''),
        ];
    return CalculatorState._(
      sessionId: sessionId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      players: resolvedPlayers,
      playerNames: List.unmodifiable([for (final p in resolvedPlayers) p.name]),
      firstDealerId: firstDealerId,
      displayedPlayers: rotatedFromDealer(resolvedPlayers, firstDealerId),
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
    );
  }

  // Private constructor for copyWith — accepts pre-computed derived lists so
  // references are preserved when the underlying data hasn't changed, keeping
  // select() callbacks stable across unrelated state mutations.
  // ignore: prefer_const_constructors_in_immutables
  const CalculatorState._({
    required this.sessionId,
    required this.createdAt,
    required this.updatedAt,
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
  });

  /// Unique ID for this game session; empty until a session is started via
  /// [CalculatorNotifier.startNewGame] or restored via
  /// [CalculatorNotifier.loadSession]. [CalculatorNotifier.reset] clears
  /// it back to empty when the session is closed or deleted.
  final String sessionId;

  /// When this session was started; null until [CalculatorNotifier.startNewGame]
  /// or [CalculatorNotifier.loadSession] populates it.
  final DateTime? createdAt;

  /// Last time meaningful content was saved (completed round, player
  /// reorder, player/dealer name change). Not updated on load or on
  /// cancelled edits.
  final DateTime? updatedAt;

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
  // Computed seat-index getters — derived on demand from ID fields.
  // ---------------------------------------------------------------------------

  int _indexOf(String id) {
    final i = players.indexWhere((p) => p.id == id);
    // Empty string is the "not yet set" sentinel — don't assert on it.
    assert(id.isEmpty || i >= 0, 'Player ID "$id" not in player list');
    return i < 0 ? 0 : i;
  }

  /// Seat index (0–3) of the current dealer.
  int get dealerIndex => _indexOf(dealerId);

  /// Seat index (0–3) of the current chooser.
  int get chooserIndex => _indexOf(chooserId);

  /// Seat index (0–3) of the round-1 dealer.
  int get firstDealerIndex => _indexOf(firstDealerId);

  /// Position of the chooser within [displayedPlayers] (0–3).
  int get displayedChooserIndex => seatIndexOf(displayedPlayers, chooserId);

  /// 1-based round counter, 1–12. Increments each time a scored game is
  /// confirmed. Resets to 1 when the first-game dealer is changed.
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

  /// True when the pending (interrupted) game has meaningful input — i.e. the
  /// user actually entered something beyond the defaults.
  bool get hasMeaningfulPendingInput {
    final p = pending;
    if (p is! ActivePendingRound) return false;
    final gameInput = p.input;
    if (gameInput == null) return false;
    return !p.game.inputDescriptor.isEmpty(gameInput);
  }

  /// Intermediate score shown while the player is still entering counts.
  /// Only set for [CountsInputDescriptor] games when the sum is > 0 but
  /// < [CountsInputDescriptor.total]. Null for recipient games.
  final ScoreResult? partialResult;

  /// Non-null when the user is re-editing an already-scored round; holds the
  /// 0-based index into [history] of the round being edited.
  final int? editingRoundIndex;

  /// True when the user is re-editing a round that was already scored.
  bool get isEditingExistingRound => editingRoundIndex != null;

  /// True when editing and the round being edited is the last one in history.
  bool get isEditingLastRound =>
      editingRoundIndex != null && editingRoundIndex == history.length - 1;

  /// True when an incomplete save during edit is allowed.
  bool get canRollbackWithPartial => isEditingLastRound;

  /// Original input/doubles/chooser captured at the start of an edit, used to
  /// detect whether anything actually changed (see [hasActiveChanges]).
  final GameInput? editOriginalInput;
  final DoubleMatrix? editOriginalDoubles;
  final String? editOriginalChooserId;

  /// True when there is meaningful active input that would be lost on cancel.
  bool get hasActiveChanges {
    if (selectedGame == null) return false;
    if (editingRoundIndex != null) {
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
    if (chooserId != players[(dealerIndex + 1) % playerCount].id) return true;
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

  CalculatorState copyWith({
    String? sessionId,
    DateTime? createdAt,
    DateTime? updatedAt,
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
    return CalculatorState._(
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
    );
  }
}

class CalculatorNotifier extends Notifier<CalculatorState> {
  @override
  CalculatorState build() {
    ref.onDispose(() {
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
    });
    return CalculatorState();
  }

  /// Pending debounced autosave timer. We coalesce bursts of state mutations
  /// (typing in the counts stepper, double-tap on a chip, etc.) into a single
  /// SharedPreferences write so we don't re-encode the entire saved-games
  /// JSON on every keystroke.
  Timer? _autosaveTimer;
  static const _autosaveDebounce = Duration(milliseconds: 400);

  @override
  set state(CalculatorState newState) {
    super.state = newState;
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    if (state.sessionId.isEmpty) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDebounce, _autosave);
  }

  Future<void> _autosave() async {
    _autosaveTimer = null;
    if (state.sessionId.isEmpty) return;
    final session = buildSession();
    if (session == null) return;
    try {
      await ref.read(gameHistoryProvider.notifier).saveGame(session);
    } on Exception catch (_) {
      // Best-effort background write; in-memory state is intact and the next
      // mutation re-triggers an autosave.
    }
  }

  /// Flushes a pending debounced autosave for the currently loaded session
  /// when it is about to be replaced by [incomingId].
  void _flushPendingAutosaveForOutgoingSession({required String incomingId}) {
    if (_autosaveTimer == null) return;
    final outgoingId = state.sessionId;
    if (outgoingId.isEmpty || outgoingId == incomingId) return;
    _autosaveTimer!.cancel();
    _autosaveTimer = null;
    final outgoing = buildSession();
    if (outgoing == null) return;
    unawaited(
      ref
          .read(gameHistoryProvider.notifier)
          .saveGame(outgoing)
          .catchError((_) {}),
    );
  }

  void setPlayerName(int index, String name) {
    final updated = List<Player>.from(state.players);
    updated[index] = updated[index].copyWith(name: name);
    state = state.copyWith(players: updated, updatedAt: DateTime.now());
  }

  /// Atomically applies a full player reorder + name updates + dealer change.
  /// Called by EditPlayersScreen so that player UUIDs stay bound to the
  /// correct seat after a drag-reorder.
  ///
  /// [firstDealerIdx] is the seat index of the player who dealt round 1.
  /// The current-round dealer is derived from that via the rotation formula.
  void setPlayersAndDealer(List<Player> players, int firstDealerIdx) {
    final nextDealerIdx = (firstDealerIdx + state.history.length) % playerCount;
    state = state.copyWith(
      players: players,
      firstDealerId: players[firstDealerIdx].id,
      dealerId: players[nextDealerIdx].id,
      updatedAt: DateTime.now(),
    );
  }

  void setDealer(int index) {
    // Back-compute firstDealerId so the next round's dealer is players[index].
    final n = state.history.length;
    final firstDealerIdx =
        ((index - n) % playerCount + playerCount) % playerCount;
    state = state.copyWith(
      firstDealerId: state.players[firstDealerIdx].id,
      dealerId: state.players[index].id,
    );
  }

  void setChooser(int index) {
    state = state.copyWith(chooserId: state.players[index].id);
    _recalculate();
  }

  void selectGame(MiniGame game) {
    // If we're resuming the same game that was interrupted, restore partial input.
    final p = state.pending;
    if (p is ActivePendingRound &&
        p.game.id == game.id &&
        state.result == null) {
      state = state.copyWith(
        selectedGame: game,
        input: p.input,
        doubles: p.doubles,
        pending: const NoPendingRound(),
      );
      _recalculate();
      return;
    }

    final defaults = game.inputDescriptor.defaults(state.players);

    state = state.copyWith(
      selectedGame: game,
      chooserId: state.players[(state.dealerIndex + 1) % playerCount].id,
      input: defaults,
      doubles: const DoubleMatrix(),
      clearResult: true,
      clearPartialResult: true,
      pending: const NoPendingRound(),
    );
  }

  /// Shared exit path used by [deselectGame], [discardGame], [cancelEditRound]
  /// and [rollbackLastRound]. Clears every slot/edit field, then derives
  /// `dealerId`, `roundNumber` and `chooserId` from [newHistory] and
  /// [CalculatorState.firstDealerId].
  CalculatorState _exitSlot(
    CalculatorState s, {
    required List<RoundRecord> newHistory,
    bool historyChanged = false,
    ActivePendingRound? overridePending,
  }) {
    // Next dealer is always derived from the initial dealer + completed rounds,
    // so this remains correct whether we're cancelling an edit of an older
    // round, deleting a round, or completing a new one.
    final nextDealerIdx =
        (s.firstDealerIndex + newHistory.length) % playerCount;
    final nextDealerId = s.players[nextDealerIdx].id;
    final nextChooserIdx = (nextDealerIdx + 1) % playerCount;
    final nextRound = newHistory.length + 1;
    return s.copyWith(
      history: newHistory,
      dealerId: nextDealerId,
      roundNumber: nextRound,
      chooserId: overridePending != null
          ? s.chooserId
          : s.players[nextChooserIdx].id,
      clearSelectedGame: true,
      clearInput: true,
      doubles: const DoubleMatrix(),
      clearResult: true,
      clearPartialResult: true,
      clearEditState: true,
      updatedAt: historyChanged ? DateTime.now() : s.updatedAt,
      pending:
          overridePending, // null → preserve s.pending; non-null → override
    );
  }

  /// Leaves the input slot.
  ///
  /// Four cases, in order:
  ///   1. Editing an existing round, slot has a valid result: replace the round.
  ///   2. Editing, slot incomplete: falls back to cancel.
  ///   3. New round, result present: append to history, advance dealer/round.
  ///   4. New round, no result but has a selected game: stash as pending.
  void deselectGame() {
    final s = state;
    final editIndex = s.editingRoundIndex;

    if (editIndex != null) {
      if (s.result == null) {
        cancelEditRound();
        return;
      }
      final replacement = RoundRecord(
        roundNumber: s.history[editIndex].roundNumber,
        game: s.selectedGame!,
        chooserId: s.chooserId,
        scoresByPlayer: Map<String, int>.from(s.result!.scores),
        input: s.input!,
        doubles: s.doubles,
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
      // New round, completed: append.
      final appended = [
        ...s.history,
        RoundRecord(
          roundNumber: s.roundNumber,
          game: s.selectedGame!,
          chooserId: s.chooserId,
          scoresByPlayer: Map<String, int>.from(s.result!.scores),
          input: s.input!,
          doubles: s.doubles,
        ),
      ];
      state = _exitSlot(s, newHistory: appended, historyChanged: true);
      return;
    }

    if (s.selectedGame != null) {
      // New round, incomplete: stash slot as pending and keep chooser.
      state = _exitSlot(
        s,
        newHistory: s.history,
        historyChanged: true,
        overridePending: ActivePendingRound(
          game: s.selectedGame!,
          input: s.input,
          doubles: s.doubles,
        ),
      );
      return;
    }

    state = _exitSlot(s, newHistory: s.history, historyChanged: true);
  }

  /// Discards any in-progress input and returns to the game selection phase
  /// without saving pending input. Used by the Cancel button for new rounds.
  void discardGame() {
    state = _exitSlot(state, newHistory: state.history);
  }

  /// Saves an incomplete edit of the last round by simply deleting that round.
  void rollbackLastRound() {
    final s = state;
    assert(
      s.isEditingLastRound,
      'rollbackLastRound called outside last-round edit (editingRoundIndex='
      '${s.editingRoundIndex}, history.length=${s.history.length})',
    );
    if (!s.isEditingLastRound) return;
    final newHistory = s.history.sublist(0, s.history.length - 1);
    state = _exitSlot(s, newHistory: newHistory, historyChanged: true);
  }

  /// Deletes the last completed round from history, rolling dealer/round back.
  void deleteLastRound() {
    if (state.history.isEmpty) return;
    final newHistory = state.history.sublist(0, state.history.length - 1);
    state = _exitSlot(state, newHistory: newHistory, historyChanged: true);
  }

  void updateInput(GameInput input) {
    if (state.input == input) return;
    state = state.copyWith(input: input);
    _recalculate();
  }

  void updateDoubles(DoubleMatrix doubles) {
    if (state.doubles == doubles) return;
    state = state.copyWith(doubles: doubles);
    _recalculate();
  }

  /// Restores a past round for re-editing. Loads the round's data into the
  /// input slot and tags [CalculatorState.editingRoundIndex] with its position
  /// in [history]; the history list itself is left untouched.
  void restoreRound(RoundRecord record) {
    final index = state.history.indexWhere(
      (r) => r.roundNumber == record.roundNumber,
    );
    assert(index >= 0, 'restoreRound: record not found in history');
    if (index < 0) return;
    final safeChooserIdx = seatIndexOf(state.players, record.chooserId);
    final dealerIdx = dealerIndexFor(safeChooserIdx);
    state = state.copyWith(
      dealerId: state.players[dealerIdx].id,
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
    if (state.editingRoundIndex == null) return;
    state = _exitSlot(state, newHistory: state.history);
  }

  /// Recalculates the result whenever the state changes, or clears it if input
  /// is no longer valid. Skips emitting when the result is unchanged.
  void _recalculate() {
    final game = state.selectedGame;
    if (game == null) return;

    if (state.inputState == InputState.complete) {
      final result = game.calculateScores(
        input: state.input!,
        doubles: state.doubles,
        players: state.players,
      );
      assert(
        result.scores.values.fold(0, (a, b) => a + b) == game.totalPoints,
        'Score sum mismatch for ${game.id}: '
        'got ${result.scores.values.fold(0, (a, b) => a + b)}, '
        'expected ${game.totalPoints}',
      );
      if (state.result == result && state.partialResult == null) return;
      state = state.copyWith(result: result, clearPartialResult: true);
    } else if (state.inputState == InputState.partial) {
      final partial = game.calculateScores(
        input: state.input!,
        doubles: state.doubles,
        players: state.players,
      );
      if (state.partialResult == partial && state.result == null) return;
      state = state.copyWith(clearResult: true, partialResult: partial);
    } else {
      if (state.result != null || state.partialResult != null) {
        state = state.copyWith(clearResult: true, clearPartialResult: true);
      }
    }
  }

  void reset() {
    state = CalculatorState();
  }

  /// Starts a brand-new game session: resets all transient state, applies the
  /// given [players] and [dealerIndex], and assigns a fresh session ID.
  void startNewGame({required List<Player> players, required int dealerIndex}) {
    final now = DateTime.now();
    state = CalculatorState(
      sessionId: '${now.microsecondsSinceEpoch}',
      createdAt: now,
      updatedAt: now,
      players: List<Player>.from(players),
      firstDealerId: players[dealerIndex].id,
      dealerId: players[dealerIndex].id,
      chooserId: players[(dealerIndex + 1) % playerCount].id,
    );
  }

  /// Builds a [GameSession] from the current state.
  ///
  /// Returns `null` when [CalculatorState.sessionId] is still empty — i.e.
  /// before [startNewGame] or [loadSession] has assigned an id.
  GameSession? buildSession() {
    if (state.sessionId.isEmpty) return null;
    final now = DateTime.now();

    PendingRound? pendingRound;
    final p = state.pending;
    if (p is ActivePendingRound) {
      pendingRound = PendingRound(
        gameId: p.game.id,
        gameName: p.game.name,
        chooserId: state.chooserId,
        input: p.input,
        doublesJson: p.doubles.hasAnyDouble ? p.doubles.toJson() : null,
      );
    }

    return GameSession(
      id: state.sessionId,
      createdAt: state.createdAt ?? now,
      updatedAt: state.updatedAt ?? state.createdAt ?? now,
      players: state.players,
      firstDealerId: state.firstDealerId,
      pendingRound: pendingRound,
      rounds: state.history,
    );
  }

  /// Restores a previously saved [GameSession] into the current state.
  void loadSession(GameSession session) {
    _flushPendingAutosaveForOutgoingSession(incomingId: session.id);

    final players = session.players;
    final safeInitialIdx = seatIndexOf(players, session.firstDealerId);

    final history = session.rounds;

    final nextDealerIdx = (safeInitialIdx + history.length) % playerCount;
    final nextRound = history.length + 1;

    PendingRoundState pendingState = const NoPendingRound();
    String chooserId = players[(nextDealerIdx + 1) % playerCount].id;
    String dealerId = players[nextDealerIdx].id;

    final savedPending = session.pendingRound;
    if (savedPending != null) {
      final matches = allGames.where((g) => g.id == savedPending.gameId);
      if (matches.isNotEmpty) {
        final pendingDoubles = savedPending.doublesJson != null
            ? DoubleMatrix.fromJson(savedPending.doublesJson!)
            : const DoubleMatrix();
        pendingState = ActivePendingRound(
          game: matches.first,
          input: savedPending.input,
          doubles: pendingDoubles,
        );
        chooserId = savedPending.chooserId;
        // Derive dealer from chooser per game rules.
        final chooserIdx = players.indexWhere(
          (p) => p.id == savedPending.chooserId,
        );
        final safeChooserIdx = chooserIdx < 0
            ? (nextDealerIdx + 1) % playerCount
            : chooserIdx;
        dealerId = players[dealerIndexFor(safeChooserIdx)].id;
      }
    }

    state = CalculatorState(
      sessionId: session.id,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      players: players,
      firstDealerId: session.firstDealerId,
      dealerId: dealerId,
      chooserId: chooserId,
      roundNumber: nextRound,
      history: history,
      pending: pendingState,
    );
  }
}

final calculatorProvider =
    NotifierProvider<CalculatorNotifier, CalculatorState>(
      CalculatorNotifier.new,
    );
