import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/double_matrix.dart';
import '../models/game_session.dart';
import '../models/games/game_catalog.dart';
import '../models/input_descriptor.dart';
import '../models/mini_game.dart';
import '../models/round_record.dart';
import '../models/score_result.dart';
import '../utils.dart';

import 'game_history_provider.dart';

/// Holds the transient state for the score calculator screen.
@immutable
class CalculatorState {
  const CalculatorState({
    this.sessionId = '',
    this.createdAt,
    this.updatedAt,
    this.playerNames = const ['', '', '', ''],
    this.dealerIndex = 0,
    this.dealerChosen = false,
    this.chooserIndex = 1,
    this.roundNumber = 1,
    this.history = const [],
    this.selectedGame,
    this.input = const {},
    this.doubles = const DoubleMatrix(),
    this.result,
    this.pendingGame,
    this.pendingInput = const {},
    this.pendingDoubles = const DoubleMatrix(),
    this.partialResult,
    this.editingRoundIndex,
    this.editOriginalInput,
    this.editOriginalDoubles,
    this.editOriginalChooserIndex,
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
  final List<String> playerNames;

  /// Index (0–3) of the player who is currently the dealer.
  /// The dealer plays the first card of the mini-game.
  final int dealerIndex;

  /// Whether the user has explicitly chosen a dealer (false until setDealer is called).
  final bool dealerChosen;

  /// Index (0–3) of the player who chose this mini-game.
  /// Defaults to left of dealer ((dealerIndex + 1) % 4) but is manually
  /// selectable per game in the input phase.
  /// Doubling order: (chooserIndex+1)%4 → … → chooserIndex (chooser doubles last).
  final int chooserIndex;

  /// 1-based round counter, 1–12.  Increments each time a scored game is
  /// confirmed.  Resets to 1 when the first-game dealer is changed.
  final int roundNumber;

  /// All completed rounds in order.
  final List<RoundRecord> history;

  final MiniGame? selectedGame;
  final Map<String, dynamic> input;
  final DoubleMatrix doubles;
  final ScoreResult? result;

  /// Partial input preserved when the user backs out of a game before finishing.
  /// Non-null only when the game was started but not yet completed.
  final MiniGame? pendingGame;
  final Map<String, dynamic> pendingInput;
  final DoubleMatrix pendingDoubles;

  /// Whether there is a partially-entered game that was interrupted.
  bool get hasPendingGame => pendingGame != null && result == null;

  /// True when the pending (interrupted) game has meaningful input — i.e. the
  /// user actually entered something beyond the defaults.
  bool get hasMeaningfulPendingInput {
    final game = pendingGame;
    if (game == null) return false;
    return !game.inputDescriptor.isEmpty(pendingInput);
  }

  /// Intermediate score shown while the player is still entering counts.
  /// Only set for [CountsInputDescriptor] games when the sum is > 0 but
  /// < [CountsInputDescriptor.total].  Null for player-picker games (partial
  /// there means nothing useful to show).
  final ScoreResult? partialResult;

  /// Non-null when the user is re-editing an already-scored round; holds the
  /// 0-based index into [history] of the round being edited.  When set, the
  /// slot fields ([selectedGame], [input], [doubles], [chooserIndex],
  /// [dealerIndex]) reflect the round being edited; [history] is left fully
  /// intact (no trimming) so the edit can be cancelled or rolled back without
  /// touching the other rounds.
  final int? editingRoundIndex;

  /// True when the user is re-editing a round that was already scored.
  bool get isEditingExistingRound => editingRoundIndex != null;

  /// True when editing and the round being edited is the last one in history
  /// (i.e. saving an incomplete edit can simply drop it without gaps).
  bool get isEditingLastRound =>
      editingRoundIndex != null && editingRoundIndex == history.length - 1;

  /// True when an incomplete save during edit is allowed: only when the round
  /// being edited is the last one, so the partial-save degrades to "delete
  /// last round".  Pending games are never affected by an edit in this model,
  /// so no extra pending-game gate is needed.
  bool get canRollbackWithPartial => isEditingLastRound;

  /// Original input/doubles/chooser captured at the start of an edit, used to
  /// detect whether anything actually changed (see [hasActiveChanges]).
  final Map<String, dynamic>? editOriginalInput;
  final DoubleMatrix? editOriginalDoubles;
  final int? editOriginalChooserIndex;

  /// Compares two input maps deeply.  Values are either int? or `List<int>`.
  static bool _inputEquals(Map<String, dynamic> a, Map<String, dynamic> b) =>
      const DeepCollectionEquality().equals(a, b);

  /// True when there is meaningful active input that would be lost on cancel.
  /// For editing an existing round, compares current input against the originals
  /// stored at the start of the edit — so it returns false when nothing changed.
  bool get hasActiveChanges {
    if (selectedGame == null) return false;
    if (editingRoundIndex != null) {
      final origInput = editOriginalInput;
      final origDoubles = editOriginalDoubles;
      final origChooser = editOriginalChooserIndex;
      if (origInput == null || origDoubles == null || origChooser == null) {
        return true; // safety fallback
      }
      if (chooserIndex != origChooser) return true;
      if (doubles != origDoubles) return true;
      if (!_inputEquals(input, origInput)) return true;
      return false;
    }
    final game = selectedGame!;
    if (!game.inputDescriptor.isEmpty(input)) return true;
    if (doubles.hasAnyDouble) return true;
    if (chooserIndex != (dealerIndex + 1) % 4) return true;
    return false;
  }

  bool get hasSomeInput {
    final game = selectedGame;
    if (game == null) return false;
    return !game.inputDescriptor.isEmpty(input);
  }

  /// True when the input is complete and ready to calculate.
  bool get isInputValid {
    final game = selectedGame;
    if (game == null) return false;
    return game.inputDescriptor.isComplete(input);
  }

  CalculatorState copyWith({
    String? sessionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? playerNames,
    int? dealerIndex,
    bool? dealerChosen,
    int? chooserIndex,
    int? roundNumber,
    List<RoundRecord>? history,
    MiniGame? selectedGame,
    bool clearSelectedGame = false,
    Map<String, dynamic>? input,
    DoubleMatrix? doubles,
    ScoreResult? result,
    bool clearResult = false,
    MiniGame? pendingGame,
    bool clearPending = false,
    Map<String, dynamic>? pendingInput,
    DoubleMatrix? pendingDoubles,
    ScoreResult? partialResult,
    bool clearPartialResult = false,
    int? editingRoundIndex,
    Map<String, dynamic>? editOriginalInput,
    DoubleMatrix? editOriginalDoubles,
    int? editOriginalChooserIndex,
    bool clearEditState = false,
  }) {
    return CalculatorState(
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      playerNames: playerNames ?? this.playerNames,
      dealerIndex: dealerIndex ?? this.dealerIndex,
      dealerChosen: dealerChosen ?? this.dealerChosen,
      chooserIndex: chooserIndex ?? this.chooserIndex,
      roundNumber: roundNumber ?? this.roundNumber,
      history: history ?? this.history,
      selectedGame: clearSelectedGame
          ? null
          : (selectedGame ?? this.selectedGame),
      input: input ?? this.input,
      doubles: doubles ?? this.doubles,
      result: clearResult ? null : (result ?? this.result),
      pendingGame: clearPending ? null : (pendingGame ?? this.pendingGame),
      pendingInput: clearPending
          ? const {}
          : (pendingInput ?? this.pendingInput),
      pendingDoubles: clearPending
          ? const DoubleMatrix()
          : (pendingDoubles ?? this.pendingDoubles),
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
      editOriginalChooserIndex: clearEditState
          ? null
          : (editOriginalChooserIndex ?? this.editOriginalChooserIndex),
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
    return const CalculatorState();
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
    } catch (_) {}
  }

  /// Flushes a pending debounced autosave for the currently loaded session
  /// when it is about to be replaced by [incomingId]. Without this, the
  /// `state =` setter inside [loadSession] would cancel the outgoing
  /// session's autosave timer and reschedule it under the new `sessionId`,
  /// silently losing edits made in the last [_autosaveDebounce] window.
  void _flushPendingAutosaveForOutgoingSession({required String incomingId}) {
    if (_autosaveTimer == null) return;
    final outgoingId = state.sessionId;
    if (outgoingId.isEmpty || outgoingId == incomingId) return;
    _autosaveTimer!.cancel();
    _autosaveTimer = null;
    final outgoing = buildSession();
    if (outgoing == null) return;
    // Fire-and-forget: callers don't need to await persistence to proceed
    // with loading the next session into memory.
    unawaited(
      ref
          .read(gameHistoryProvider.notifier)
          .saveGame(outgoing)
          .catchError((_) {}),
    );
  }

  void setPlayerName(int index, String name) {
    final updated = List<String>.from(state.playerNames);
    updated[index] = name;
    state = state.copyWith(playerNames: updated, updatedAt: DateTime.now());
  }

  /// Reorders the player names list, moving the entry at [oldIndex] to
  /// [newIndex] (using the same convention as [ReorderableListView]).
  ///
  /// If the dealer was already chosen, the dealer index is updated so it
  /// keeps pointing at the same person after the move.
  void reorderPlayerNames(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final names = List<String>.from(state.playerNames);
    if (oldIndex < 0 || oldIndex >= names.length) return;
    // ReorderableListView uses an "insert before" convention where newIndex
    // can equal names.length and is one greater than the source position
    // when moving down.
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= names.length) target = names.length - 1;
    final moved = names.removeAt(oldIndex);
    names.insert(target, moved);

    // Recompute dealer index so it still points at the same person.
    var dealer = state.dealerIndex;
    if (state.dealerChosen) {
      dealer = adjustIndexAfterReorder(oldIndex, target, dealer);
    }

    state = state.copyWith(
      playerNames: names,
      dealerIndex: dealer,
      updatedAt: DateTime.now(),
    );
  }

  void setDealer(int index) {
    // Updates who is dealing the current round.  Past rounds in [history] keep
    // their recorded dealer and are not retroactively re-rotated.  Subsequent
    // rounds will continue to rotate from this new dealer.
    state = state.copyWith(dealerIndex: index, dealerChosen: true);
  }

  void setChooser(int index) {
    state = state.copyWith(chooserIndex: index);
    _recalculate();
  }

  void selectGame(MiniGame game) {
    // If we're resuming the same game that was interrupted, restore partial input.
    if (state.pendingGame?.id == game.id && state.result == null) {
      state = state.copyWith(
        selectedGame: game,
        input: state.pendingInput,
        doubles: state.pendingDoubles,
        clearPending: true,
      );
      _recalculate();
      return;
    }

    // Counts: pre-fill with zeros.  Player-picker games start unselected.
    final defaults = game.inputDescriptor.defaults();

    state = state.copyWith(
      selectedGame: game,
      chooserIndex: (state.dealerIndex + 1) % 4,
      input: defaults,
      doubles: const DoubleMatrix(),
      clearResult: true,
      clearPartialResult: true,
      clearPending: true,
    );
  }

  /// Shared exit path used by [deselectGame], [discardGame], [cancelEditRound]
  /// and [rollbackLastRound] (and indirectly by [deleteLastRound]).  Clears
  /// every slot/edit field, then derives `dealerIndex`, `roundNumber` and
  /// `chooserIndex` from [newHistory] using the standard "next-round"
  /// formulas, so the caller never has to recompute them by hand.
  ///
  /// Callers that need to keep a [pendingGame] in flight (the legitimate
  /// "save partial as pending" path) should NOT use this helper directly —
  /// they pass [overridePending] to set new pending fields.  Pending state is
  /// otherwise preserved across edits and discards.
  ///
  /// [historyChanged] controls whether [CalculatorState.updatedAt] is bumped:
  /// pure cancels/discards leave it alone so they don't churn the autosave.
  CalculatorState _exitSlot(
    CalculatorState s, {
    required List<RoundRecord> newHistory,
    bool historyChanged = false,
    _PendingSlot? overridePending,
  }) {
    final nextDealer = newHistory.isEmpty
        ? s.dealerIndex
        : (newHistory.last.dealerIndex + 1) % 4;
    final nextRound = newHistory.length + 1;
    final next = s.copyWith(
      history: newHistory,
      dealerIndex: nextDealer,
      roundNumber: nextRound,
      chooserIndex: overridePending != null
          ? s.chooserIndex
          : (nextDealer + 1) % 4,
      clearSelectedGame: true,
      input: const {},
      doubles: const DoubleMatrix(),
      clearResult: true,
      clearPartialResult: true,
      clearEditState: true,
      updatedAt: historyChanged ? DateTime.now() : s.updatedAt,
    );
    if (overridePending != null) {
      return next.copyWith(
        pendingGame: overridePending.game,
        pendingInput: overridePending.input,
        pendingDoubles: overridePending.doubles,
      );
    }
    return next;
  }

  /// Leaves the input slot.
  ///
  /// Four cases, in order:
  ///   1. Editing an existing round, slot has a valid [CalculatorState.result]:
  ///      replace `history[editingRoundIndex]` with the new record.
  ///   2. Editing, slot incomplete: caller should have routed to
  ///      [rollbackLastRound] (last round) or [cancelEditRound] (older round);
  ///      this method falls back to cancel for safety.
  ///   3. New round, result present: append to history, advance dealer/round.
  ///   4. New round, no result but has a selected game: stash as pending so
  ///      the user can resume it later.
  void deselectGame() {
    final s = state;
    final editIndex = s.editingRoundIndex;

    if (editIndex != null) {
      if (s.result == null) {
        // Defensive: incomplete edit save shouldn't reach here for older
        // rounds (button is disabled) and for the last round routes to
        // rollbackLastRound.  Treat as cancel.
        cancelEditRound();
        return;
      }
      final replacement = RoundRecord(
        roundNumber: s.history[editIndex].roundNumber,
        game: s.selectedGame!,
        dealerIndex: s.dealerIndex,
        chooserIndex: s.chooserIndex,
        input: s.input,
        doubles: s.doubles,
        result: s.result!,
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
          dealerIndex: s.dealerIndex,
          chooserIndex: s.chooserIndex,
          input: s.input,
          doubles: s.doubles,
          result: s.result!,
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
        overridePending: _PendingSlot(
          game: s.selectedGame,
          input: s.input,
          doubles: s.doubles,
        ),
      );
      return;
    }

    // Empty slot: just clear (preserves the legacy "clears any stale
    // pending" behaviour by passing no overridePending and routing through
    // the default clearing path).
    state = _exitSlot(s, newHistory: s.history, historyChanged: true);
  }

  /// Discards any in-progress input and returns to the game selection phase
  /// without saving pending input.  Used by the Cancel button for new rounds.
  void discardGame() {
    state = _exitSlot(state, newHistory: state.history);
  }

  /// Saves an incomplete edit of the last round by simply deleting that round.
  /// Only valid when [CalculatorState.isEditingLastRound] is true — enforced
  /// by an assert so any future regression of the gating logic surfaces here.
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

  void updateInput(String key, dynamic value) {
    if (const DeepCollectionEquality().equals(state.input[key], value)) return;
    state = state.copyWith(input: {...state.input, key: value});
    _recalculate();
  }

  void updateDoubles(DoubleMatrix doubles) {
    if (state.doubles == doubles) return;
    state = state.copyWith(doubles: doubles);
    _recalculate();
  }

  /// Restores a past round for re-editing.  Loads the round's data into the
  /// input slot and tags [CalculatorState.editingRoundIndex] with its position
  /// in [history]; the history list itself is left untouched, and any
  /// in-flight [pendingGame] is preserved across the edit.
  void restoreRound(RoundRecord record) {
    final index = state.history.indexWhere(
      (r) => r.roundNumber == record.roundNumber,
    );
    assert(index >= 0, 'restoreRound: record not found in history');
    if (index < 0) return;
    state = state.copyWith(
      dealerIndex: record.dealerIndex,
      chooserIndex: record.chooserIndex,
      roundNumber: record.roundNumber,
      selectedGame: record.game,
      input: record.input,
      doubles: record.doubles,
      result: record.result,
      clearPartialResult: true,
      editingRoundIndex: index,
      editOriginalInput: Map<String, dynamic>.from(record.input),
      editOriginalDoubles: record.doubles,
      editOriginalChooserIndex: record.chooserIndex,
    );
  }

  /// Cancels an in-progress edit of an existing round.  Because [history] was
  /// never mutated during the edit, this just clears the slot and recomputes
  /// the next-round dealer / round / chooser from history.  Pending state is
  /// left untouched.
  void cancelEditRound() {
    if (state.editingRoundIndex == null) return;
    state = _exitSlot(state, newHistory: state.history);
  }

  /// Recalculates the result whenever the state changes, or clears it if input
  /// is no longer valid.  Called automatically after every input mutation.
  ///
  /// Skips emitting a new state when the result is unchanged — this prevents
  /// no-op rebuilds (e.g. user taps + then − returning to the same counts)
  /// and avoids triggering the debounced autosave for a state that's
  /// effectively identical.
  void _recalculate() {
    final game = state.selectedGame;
    if (game == null) return;

    if (state.isInputValid) {
      final result = game.calculateScores(
        input: state.input,
        doubles: state.doubles,
      );
      if (state.result == result && state.partialResult == null) return;
      state = state.copyWith(result: result, clearPartialResult: true);
    } else if (state.hasSomeInput) {
      final partial = game.calculateScores(
        input: state.input,
        doubles: state.doubles,
      );
      if (state.partialResult == partial && state.result == null) return;
      state = state.copyWith(clearResult: true, partialResult: partial);
    } else {
      if (state.result != null || state.partialResult != null) {
        state = state.copyWith(clearResult: true, clearPartialResult: true);
      }
    }
  }

  void calculate() {
    final game = state.selectedGame;
    if (game == null || !state.isInputValid) return;

    final result = game.calculateScores(
      input: state.input,
      doubles: state.doubles,
    );
    state = state.copyWith(result: result);
  }

  void reset() {
    state = const CalculatorState(
      playerNames: ['', '', '', ''],
      dealerChosen: false,
    );
  }

  /// Starts a brand-new game session in a single state update: resets all
  /// transient state, applies the given player [names] and [dealerIndex],
  /// and assigns a fresh session ID.
  void startNewGame({required List<String> names, required int dealerIndex}) {
    final now = DateTime.now();
    state = CalculatorState(
      sessionId: '${now.microsecondsSinceEpoch}',
      createdAt: now,
      updatedAt: now,
      playerNames: List<String>.from(names),
      dealerIndex: dealerIndex,
      dealerChosen: true,
    );
  }

  /// Builds a [GameSession] from the current state.
  ///
  /// Returns `null` when [CalculatorState.sessionId] is still empty — i.e.
  /// before [startNewGame] or [loadSession] has assigned an id. This is
  /// reachable from the autosave scheduler, which fires for any state
  /// mutation including the very first player-name edits on the setup
  /// screen; persisting nothing in that window is intentional.
  GameSession? buildSession() {
    if (state.sessionId.isEmpty) return null;
    final now = DateTime.now();

    PendingRound? pendingRound;
    if (state.pendingGame != null) {
      pendingRound = PendingRound(
        gameId: state.pendingGame!.id,
        gameName: state.pendingGame!.name,
        dealerIndex: state.dealerIndex,
        chooserIndex: state.chooserIndex,
        input: state.pendingInput,
        doublesJson: state.pendingDoubles.hasAnyDouble
            ? state.pendingDoubles.toJson()
            : null,
      );
    }

    return GameSession(
      id: state.sessionId.isEmpty
          ? '${now.microsecondsSinceEpoch}'
          : state.sessionId,
      createdAt: state.createdAt ?? now,
      updatedAt: state.updatedAt ?? state.createdAt ?? now,
      playerNames: state.playerNames,
      pendingRound: pendingRound,
      rounds: [
        for (final r in state.history)
          RoundSummary(
            roundNumber: r.roundNumber,
            gameName: r.game.name,
            gameId: r.game.id,
            dealerIndex: r.dealerIndex,
            chooserIndex: r.chooserIndex,
            scores: r.result.scores,
            input: r.input,
            doublesJson: r.doubles.toJson(),
          ),
      ],
    );
  }

  /// Restores a previously saved [GameSession] into the current state so the
  /// player can continue or edit it.
  ///
  /// If a debounced autosave is still pending for a *different* outgoing
  /// session, it is flushed synchronously-scheduled before the state swap so
  /// last-second edits (e.g. a partial round just started before navigating
  /// back to the home screen) aren't dropped when the timer would otherwise
  /// be cancelled and rescheduled under the incoming `sessionId`.
  void loadSession(GameSession session) {
    _flushPendingAutosaveForOutgoingSession(incomingId: session.id);

    final history = [
      for (final s in session.rounds)
        RoundRecord(
          roundNumber: s.roundNumber,
          game: allGames.firstWhere(
            (g) => g.id == s.gameId,
            orElse: () => allGames.first,
          ),
          dealerIndex: s.dealerIndex,
          chooserIndex: s.chooserIndex,
          input: s.input ?? const {},
          doubles: s.doublesJson != null
              ? DoubleMatrix.fromJson(s.doublesJson!)
              : const DoubleMatrix(),
          result: ScoreResult(scores: s.scores),
        ),
    ];

    final nextDealer = history.isEmpty ? 0 : (history.last.dealerIndex + 1) % 4;
    final nextRound = history.length + 1;

    MiniGame? pendingGame;
    Map<String, dynamic> pendingInput = const {};
    DoubleMatrix pendingDoubles = const DoubleMatrix();
    int chooserIndex = (nextDealer + 1) % 4;

    final pending = session.pendingRound;
    if (pending != null) {
      final matches = allGames.where((g) => g.id == pending.gameId);
      if (matches.isNotEmpty) {
        pendingGame = matches.first;
        pendingInput = pending.input;
        pendingDoubles = pending.doublesJson != null
            ? DoubleMatrix.fromJson(pending.doublesJson!)
            : const DoubleMatrix();
        chooserIndex = pending.chooserIndex;
      }
    }

    state = CalculatorState(
      sessionId: session.id,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      playerNames: session.playerNames,
      dealerIndex: nextDealer,
      chooserIndex: chooserIndex,
      roundNumber: nextRound,
      history: history,
      pendingGame: pendingGame,
      pendingInput: pendingInput,
      pendingDoubles: pendingDoubles,
    );
  }
}

final calculatorProvider =
    NotifierProvider<CalculatorNotifier, CalculatorState>(
      CalculatorNotifier.new,
    );

/// Lightweight bundle for [CalculatorNotifier._exitSlot] when the slot's
/// contents should be promoted into the pending-game fields instead of being
/// discarded.
class _PendingSlot {
  const _PendingSlot({
    required this.game,
    required this.input,
    required this.doubles,
  });
  final MiniGame? game;
  final Map<String, dynamic> input;
  final DoubleMatrix doubles;
}
