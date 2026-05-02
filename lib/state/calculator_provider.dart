import 'dart:async';

import 'package:collection/collection.dart';
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
    this.isEditingExistingRound = false,
    this.hadPendingGameBeforeEdit = false,
    this.editOriginalInput,
    this.editOriginalDoubles,
    this.editOriginalChooserIndex,
  });

  /// Unique ID for this game session; empty until [CalculatorNotifier.reset]
  /// is called.
  final String sessionId;

  /// When this session was started; null until reset() is called.
  final DateTime? createdAt;

  /// Last time meaningful content was saved (completed round, reorder,
  /// player/dealer change). Not updated on load or on cancelled edits.
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

  /// True when the user is re-editing a round that was already scored.
  final bool isEditingExistingRound;

  /// True when there was already a pending game in progress at the moment the
  /// user began editing an existing round.  Saving a partial rollback is blocked
  /// in this case because it would overwrite that pending game.
  final bool hadPendingGameBeforeEdit;

  /// True when editing and the round being edited is the last one (i.e. it can
  /// be safely rolled back without gaps in history).
  bool get isEditingLastRound =>
      isEditingExistingRound && history.length + 1 == roundNumber;

  /// True when editing the last round AND there was no pending game before the
  /// edit started — meaning the user can save a partial rollback.
  bool get canRollbackWithPartial =>
      isEditingLastRound && !hadPendingGameBeforeEdit;

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
    if (isEditingExistingRound) {
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
    bool? isEditingExistingRound,
    bool? hadPendingGameBeforeEdit,
    Map<String, dynamic>? editOriginalInput,
    DoubleMatrix? editOriginalDoubles,
    int? editOriginalChooserIndex,
    bool clearEditOriginals = false,
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
      isEditingExistingRound:
          isEditingExistingRound ?? this.isEditingExistingRound,
      hadPendingGameBeforeEdit:
          hadPendingGameBeforeEdit ?? this.hadPendingGameBeforeEdit,
      editOriginalInput: clearEditOriginals
          ? null
          : (editOriginalInput ?? this.editOriginalInput),
      editOriginalDoubles: clearEditOriginals
          ? null
          : (editOriginalDoubles ?? this.editOriginalDoubles),
      editOriginalChooserIndex: clearEditOriginals
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

  /// Snapshot taken just before restoreRound(), used by cancelEditRound().
  CalculatorState? _editSnapshot;

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

  void setPlayerName(int index, String name) {
    final updated = List<String>.from(state.playerNames);
    updated[index] = name;
    state = state.copyWith(playerNames: updated, updatedAt: DateTime.now());
  }

  /// Replaces all player names at once.
  void setAllPlayerNames(List<String> names) {
    state = state.copyWith(
      playerNames: List<String>.from(names),
      updatedAt: DateTime.now(),
    );
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
    state = state.copyWith(
      dealerIndex: index,
      dealerChosen: true,
    );
  }

  /// Clears the explicit dealer choice so that a random dealer will be picked
  /// when the game starts. Only meaningful before the first round is recorded.
  void clearDealer() {
    state = state.copyWith(dealerChosen: false);
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

  void deselectGame() {
    final completed = state.result != null;
    final isEditing = state.isEditingExistingRound;
    // When finishing an edit, restore dealer/round from the snapshot so we
    // don't advance past rounds that already exist after the edited one.
    final nextDealer = (completed && !isEditing)
        ? (state.dealerIndex + 1) % 4
        : (isEditing && _editSnapshot != null)
        ? _editSnapshot!.dealerIndex
        : state.dealerIndex;
    final nextRound = (completed && !isEditing)
        ? state.roundNumber + 1
        : (isEditing && _editSnapshot != null)
        ? _editSnapshot!.roundNumber
        : state.roundNumber;
    final updatedHistory = completed
        ? [
            ...state.history,
            RoundRecord(
              roundNumber: state.roundNumber,
              game: state.selectedGame!,
              dealerIndex: state.dealerIndex,
              chooserIndex: state.chooserIndex,
              input: state.input,
              doubles: state.doubles,
              result: state.result!,
            ),
            // When finishing an edit, re-append rounds that came *after* the
            // edited one (they were stripped by restoreRound but are still valid).
            if (state.isEditingExistingRound && _editSnapshot != null)
              ..._editSnapshot!.history.where(
                (r) => r.roundNumber > state.roundNumber,
              ),
          ]
        : state.history;

    // Preserve partial input so the user can resume the same game later.
    // When finishing an edit of an existing round, restore the pending game
    // that was active before the edit started (captured in _editSnapshot).
    final MiniGame? savedPendingGame;
    final Map<String, dynamic> savedPendingInput;
    final DoubleMatrix savedPendingDoubles;
    if (state.isEditingExistingRound && _editSnapshot != null) {
      savedPendingGame = _editSnapshot!.pendingGame;
      savedPendingInput = _editSnapshot!.pendingInput;
      savedPendingDoubles = _editSnapshot!.pendingDoubles;
    } else if (!completed && state.selectedGame != null) {
      savedPendingGame = state.selectedGame;
      savedPendingInput = state.input;
      savedPendingDoubles = state.doubles;
    } else {
      savedPendingGame = null;
      savedPendingInput = const {};
      savedPendingDoubles = const DoubleMatrix();
    }

    state = state.copyWith(
      clearSelectedGame: true,
      dealerIndex: nextDealer,
      // When saving as pending, keep the chooser the user set so it's restored
      // when resuming. Only reset to the next-dealer default for a fresh round.
      chooserIndex: savedPendingGame != null
          ? state.chooserIndex
          : (nextDealer + 1) % 4,
      roundNumber: nextRound,
      history: updatedHistory,
      pendingGame: savedPendingGame,
      pendingInput: savedPendingInput,
      pendingDoubles: savedPendingDoubles,
      clearPending: savedPendingGame == null,
      clearResult: true,
      clearPartialResult: true,
      input: const {},
      doubles: const DoubleMatrix(),
      isEditingExistingRound: false,
      clearEditOriginals: true,
      updatedAt: DateTime.now(),
    );
    _editSnapshot = null;
  }

  /// Discards any in-progress input and returns to the game selection phase
  /// without saving pending input.  Used by the Cancel button for new rounds.
  void discardGame() {
    state = state.copyWith(
      clearSelectedGame: true,
      clearResult: true,
      clearPartialResult: true,
      clearEditOriginals: true,
      input: const {},
      doubles: const DoubleMatrix(),
    );
  }

  /// Rolls back the last round: keeps the already-trimmed history, deselects
  /// the game, and restores any pending game that existed before the edit.
  void rollbackLastRound() {
    // Restore the pending game that was active before the edit started.
    final snap = _editSnapshot;
    final restoredPendingGame = snap?.pendingGame;
    final restoredPendingInput =
        snap?.pendingInput ?? const <String, dynamic>{};
    final restoredPendingDoubles = snap?.pendingDoubles ?? const DoubleMatrix();
    state = state.copyWith(
      clearSelectedGame: true,
      pendingGame: restoredPendingGame,
      pendingInput: restoredPendingInput,
      pendingDoubles: restoredPendingDoubles,
      clearPending: restoredPendingGame == null,
      clearResult: true,
      clearPartialResult: true,
      clearEditOriginals: true,
      input: const {},
      doubles: const DoubleMatrix(),
      isEditingExistingRound: false,
      hadPendingGameBeforeEdit: false,
      updatedAt: DateTime.now(),
    );
    _editSnapshot = null;
  }

  /// Deletes the last completed round from history, rolling dealer/round back.
  void deleteLastRound() {
    if (state.history.isEmpty) return;
    final newHistory = state.history.sublist(0, state.history.length - 1);
    final last = state.history.last;
    state = state.copyWith(
      history: newHistory,
      dealerIndex: last.dealerIndex,
      chooserIndex: (last.dealerIndex + 1) % 4,
      roundNumber: last.roundNumber,
      updatedAt: DateTime.now(),
    );
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

  /// Replaces history with the given list (used to revert a reorder).
  void restoreHistory(List<RoundRecord> history) {
    state = state.copyWith(history: history);
  }

  /// Reorders history by moving the round at [oldIndex] to [newIndex],
  /// then renumbers all rounds sequentially (1-based).
  void reorderRounds(int oldIndex, int newIndex) {
    final list = List<RoundRecord>.from(state.history);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final renumbered = [
      for (int i = 0; i < list.length; i++) list[i].copyWith(roundNumber: i + 1),
    ];
    state = state.copyWith(history: renumbered, updatedAt: DateTime.now());
  }

  /// Restore a past round for re-editing.  Removes that round and all
  /// subsequent rounds from history (they may become invalid after a fix).
  void restoreRound(RoundRecord record) {
    _editSnapshot = state;
    final hadPending = state.hasPendingGame;
    final trimmedHistory = state.history
        .where((r) => r.roundNumber < record.roundNumber)
        .toList();
    state = state.copyWith(
      dealerIndex: record.dealerIndex,
      chooserIndex: record.chooserIndex,
      roundNumber: record.roundNumber,
      history: trimmedHistory,
      selectedGame: record.game,
      input: record.input,
      doubles: record.doubles,
      result: record.result,
      clearPending: true,
      clearPartialResult: true,
      isEditingExistingRound: true,
      hadPendingGameBeforeEdit: hadPending,
      editOriginalInput: Map<String, dynamic>.from(record.input),
      editOriginalDoubles: record.doubles,
      editOriginalChooserIndex: record.chooserIndex,
    );
  }

  /// Cancels an in-progress edit of an existing round, restoring the full
  /// state (including history) to what it was before the edit began.
  void cancelEditRound() {
    final snapshot = _editSnapshot;
    if (snapshot != null) {
      _editSnapshot = null;
      state = snapshot;
    }
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
  /// and assigns a fresh session ID. Equivalent to
  /// `reset()` + `setAllPlayerNames` + `setDealer` + `initSession`, but as
  /// one atomic emission so the autosave only fires once.
  void startNewGame({
    required List<String> names,
    required int dealerIndex,
  }) {
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

  /// Assigns a fresh session ID to the current state, marking it as a
  /// real game that should be persisted.  Call this exactly once, when
  /// the user confirms "Start spel".
  void initSession() {
    final now = DateTime.now();
    state = state.copyWith(
      sessionId: '${now.microsecondsSinceEpoch}',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Builds a [GameSession] from the current state.
  /// Returns null if the session has not been initialised yet.
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
  void loadSession(GameSession session) {
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
