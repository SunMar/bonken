import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/games/game_catalog.dart';
import '../models/mini_game.dart';
import '../models/round_record.dart';
import '../models/score_result.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/dialogs.dart';
import '../widgets/doubles_chips.dart';
import '../widgets/doubles_picker.dart';
import '../widgets/drag_handle.dart';
import '../widgets/game_input/game_input_form.dart';
import '../widgets/player_list_field.dart';
import '../widgets/score_result_view.dart';
import 'setup_screen.dart';
import 'start_screen.dart';

/// Scoped to the CalculatorScreen lifetime — true while reorder mode is active.
class _IsReorderModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final isReorderModeProvider =
    NotifierProvider.autoDispose<_IsReorderModeNotifier, bool>(
      _IsReorderModeNotifier.new,
    );

/// Snapshot of history order taken when entering reorder mode, used for Cancel.
class _ReorderSnapshotNotifier extends Notifier<List<RoundRecord>> {
  @override
  List<RoundRecord> build() => const [];
  void set(List<RoundRecord> snapshot) => state = snapshot;
}

final reorderSnapshotProvider =
    NotifierProvider.autoDispose<_ReorderSnapshotNotifier, List<RoundRecord>>(
      _ReorderSnapshotNotifier.new,
    );

/// True while the edit-players page is shown in place of the game list.
class _IsEditPlayersModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final isEditPlayersModeProvider =
    NotifierProvider.autoDispose<_IsEditPlayersModeNotifier, bool>(
      _IsEditPlayersModeNotifier.new,
    );

/// Incremented by the AppBar "Opslaan" button to signal _EditPlayersPhase
/// that it should commit its local form state to the provider.
class _EditPlayersSaveTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void fire() => state++;
}

final _editPlayersSaveTriggerProvider =
    NotifierProvider.autoDispose<_EditPlayersSaveTriggerNotifier, int>(
      _EditPlayersSaveTriggerNotifier.new,
    );

/// True when all player name fields are non-empty (save is allowed).
class _CanSavePlayersNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool value) => state = value;
}

final _canSavePlayersProvider =
    NotifierProvider.autoDispose<_CanSavePlayersNotifier, bool>(
      _CanSavePlayersNotifier.new,
    );

/// True when the edit-players form has unsaved changes.
class _HasPlayersChangesNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final _hasPlayersChangesProvider =
    NotifierProvider.autoDispose<_HasPlayersChangesNotifier, bool>(
      _HasPlayersChangesNotifier.new,
    );

// Game symbols displayed next to each game name in the selection list.
// The four playing-card suits are NOT rendered from Unicode characters: on
// Android the text shaper falls back to Noto Color Emoji for ♣ ♦ ♥ ♠ even
// with the U+FE0E (VS15) text-presentation selector appended, which means the
// suits would render as colored emoji. Instead, the suit-based games render
// as vector icons (see [_GameSymbol]); the entries below are only used as a
// safety fallback for the non-suit games.
const _gameSymbols = {
  'noTrump': 'SA',
  'kingOfHearts': '',
  'kingsAndJacks': 'H/B',
  'queens': 'V',
  'duck': '▼',
  'heartPoints': '',
  'seventhAndThirteenth': '7/13',
  'finalTrick': '★',
  'dominoes': 'D',
};

// Per-suit accent colors. Games not in this map fall back to the
// positive/negative theme color.
const _gameColors = {
  'clubs': Color(0xFF3A3A3A), // dark grey
  'spades': Color(0xFF0D2B4E), // deep marine blue
  'diamonds': Color(0xFFCC6600), // muted orange
  'hearts': Color(0xFFB52424), // muted red
};

// Shared body text for "discard your edits" confirmation dialogs.
const _discardChangesMessage = 'Je wijzigingen gaan verloren.';

/// Standard confirmation dialog used whenever the user is about to abandon
/// unsaved edits. Returns true if the user confirms the discard.
Future<bool> _confirmDiscardChanges(
  BuildContext context, {
  String title = 'Wijzigingen verwerpen',
  String contentText = _discardChangesMessage,
}) async {
  final confirm = await showConfirmDialog(
    context,
    title: title,
    contentText: contentText,
    confirmLabel: 'Verwerpen',
    destructive: true,
  );
  return confirm == true;
}

// =============================================================================
// CalculatorScreen — top-level screen
// =============================================================================

class CalculatorScreen extends ConsumerWidget {
  const CalculatorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(calculatorProvider.select((s) => s.selectedGame));
    final isReordering = ref.watch(isReorderModeProvider);
    final isEditingPlayers = ref.watch(isEditPlayersModeProvider);
    final canSavePlayers = ref.watch(_canSavePlayersProvider);
    final hasPlayersChanges = ref.watch(_hasPlayersChangesProvider);
    final isEditing = ref.watch(
      calculatorProvider.select((s) => s.isEditingExistingRound),
    );
    final isEditingLastRound = ref.watch(
      calculatorProvider.select((s) => s.canRollbackWithPartial),
    );
    final isInputValid = ref.watch(
      calculatorProvider.select((s) => s.isInputValid),
    );

    void cancelInputPhase() {
      if (isEditing) {
        ref.read(calculatorProvider.notifier).cancelEditRound();
      } else {
        ref.read(calculatorProvider.notifier).discardGame();
      }
    }

    Future<void> confirmAndCancelInput() async {
      final hasChanges = ref.read(
        calculatorProvider.select((s) => s.hasActiveChanges),
      );
      if (hasChanges) {
        if (!context.mounted) return;
        final confirmed = await _confirmDiscardChanges(
          context,
          title: isEditing ? 'Wijzigingen verwerpen' : 'Invoer verwerpen',
          contentText: isEditing
              ? _discardChangesMessage
              : 'Je ingevoerde gegevens gaan verloren.',
        );
        if (!confirmed) return;
      }
      cancelInputPhase();
    }

    Future<void> saveOrConfirmBack() async {
      final state = ref.read(calculatorProvider);
      if (state.isEditingExistingRound) {
        // Back while editing = discard path, same as Verwerpen.
        if (state.hasActiveChanges) {
          if (!context.mounted) return;
          final confirmed = await _confirmDiscardChanges(
            context,
            title: 'Wijzigingen niet opgeslagen',
          );
          if (!confirmed) return;
        }
        ref.read(calculatorProvider.notifier).cancelEditRound();
        return;
      }
      if (state.hasActiveChanges) {
        if (!context.mounted) return;
        final confirm = await showConfirmDialog(
          context,
          title: 'Ronde niet afgerond',
          contentText:
              'Deze ronde is nog niet gescoord. Wil je de invoer verwerpen?',
          confirmLabel: 'Verwerpen',
          destructive: true,
        );
        if (confirm != true) return;
      }
      ref.read(calculatorProvider.notifier).discardGame();
    }

    Future<void> showEditingIncompleteDialog() async {
      if (!context.mounted) return;
      await showInfoDialog(
        context,
        title: 'Score niet compleet',
        contentText:
            'Je bent een al gespeelde ronde aan het bewerken. '
            'Vul de score volledig in voordat je kunt opslaan.',
      );
    }

    Future<void> saveOrConfirmDone() async {
      final state = ref.read(calculatorProvider);
      if (state.result != null) {
        if (state.hasActiveChanges) {
          if (!context.mounted) return;
          final confirm = await showConfirmDialog(
            context,
            title: 'Score',
            content: SingleChildScrollView(
              child: ScoreResultView(
                result: state.result!,
                game: state.selectedGame!,
                playerNames: state.playerNames,
                doubles: state.doubles,
                chooserIndex: state.chooserIndex,
                showHeader: false,
              ),
            ),
            confirmLabel: 'Opslaan',
          );
          if (confirm != true) return;
        }
        // Fully scored — save.
        ref.read(calculatorProvider.notifier).deselectGame();
        return;
      }
      if (state.isEditingExistingRound) {
        if (state.canRollbackWithPartial) {
          if (!context.mounted) return;
          final confirm = await showConfirmDialog(
            context,
            title: 'Score niet compleet',
            contentText:
                'De score is nog niet compleet. Wil je toch doorgaan met opslaan?',
            confirmLabel: 'Opslaan',
          );
          if (confirm != true) return;
          ref.read(calculatorProvider.notifier).rollbackLastRound();
          return;
        }
        await showEditingIncompleteDialog();
        return;
      }
      if (!state.hasActiveChanges) {
        // Nothing entered — treat as discard, no confirmation needed.
        ref.read(calculatorProvider.notifier).discardGame();
        return;
      }
      // hasActiveChanges is true — always confirm before saving as pending.
      if (!context.mounted) return;
      final confirm = await showConfirmDialog(
        context,
        title: 'Score niet compleet',
        contentText:
            'De score is nog niet compleet. Wil je toch doorgaan met opslaan?',
        confirmLabel: 'Opslaan',
      );
      if (confirm != true) return;
      ref.read(calculatorProvider.notifier).deselectGame();
    }

    Future<void> confirmAndCancelPlayers() async {
      if (hasPlayersChanges) {
        if (!context.mounted) return;
        final confirmed = await _confirmDiscardChanges(context);
        if (!confirmed) return;
      }
      ref.read(isEditPlayersModeProvider.notifier).set(false);
    }

    Future<void> confirmAndCancelReorder() async {
      final snapshot = ref.read(reorderSnapshotProvider);
      final current = ref.read(calculatorProvider).history;
      final hasChanges =
          snapshot.length == current.length &&
          Iterable<int>.generate(
            snapshot.length,
          ).any((i) => snapshot[i].game.id != current[i].game.id);
      if (hasChanges) {
        if (!context.mounted) return;
        final confirmed = await _confirmDiscardChanges(
          context,
          contentText:
              'Je wijzigingen aan de volgorde worden niet opgeslagen.',
        );
        if (!confirmed) return;
      }
      ref
          .read(calculatorProvider.notifier)
          .restoreHistory(ref.read(reorderSnapshotProvider));
      ref.read(isReorderModeProvider.notifier).set(false);
    }

    Future<void> handleBack() async {
      if (isEditingPlayers) {
        await confirmAndCancelPlayers();
      } else if (isReordering) {
        await confirmAndCancelReorder();
      } else if (game != null) {
        await saveOrConfirmBack();
      }
    }

    return PopScope(
      // Allow native back when no game is selected (pops to HomeScreen).
      // When a game is selected, intercept back to deselect instead.
      // While reordering or editing players, intercept back to cancel.
      canPop: game == null && !isReordering && !isEditingPlayers,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bonken'),
          leading: game != null || isReordering || isEditingPlayers
              ? IconButton(
                  icon: const Icon(Symbols.arrow_back),
                  tooltip: 'Verwerpen',
                  onPressed: handleBack,
                )
              : null,
          actions: [
            if (isEditingPlayers) ...[
              TextButton(
                onPressed: () => confirmAndCancelPlayers(),
                child: const Text('Verwerpen'),
              ),
              FilledButton(
                onPressed: canSavePlayers
                    ? () => ref
                          .read(_editPlayersSaveTriggerProvider.notifier)
                          .fire()
                    : null,
                child: const Text('Opslaan'),
              ),
              const SizedBox(width: 4),
            ] else if (isReordering) ...[
              TextButton(
                onPressed: () => confirmAndCancelReorder(),
                child: const Text('Verwerpen'),
              ),
              FilledButton(
                onPressed: () =>
                    ref.read(isReorderModeProvider.notifier).set(false),
                child: const Text('Opslaan'),
              ),
              const SizedBox(width: 4),
            ] else if (game != null) ...[
              TextButton(
                onPressed: () => confirmAndCancelInput(),
                child: const Text('Verwerpen'),
              ),
              GestureDetector(
                onTap: (isEditing && !isInputValid && !isEditingLastRound)
                    ? () => showEditingIncompleteDialog()
                    : null,
                child: FilledButton(
                  onPressed: (isEditing && !isInputValid && !isEditingLastRound)
                      ? null
                      : () => saveOrConfirmDone(),
                  child: const Text('Opslaan'),
                ),
              ),
              const SizedBox(width: 4),
            ] else
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'reorder') {
                    ref
                        .read(reorderSnapshotProvider.notifier)
                        .set(List.of(ref.read(calculatorProvider).history));
                    ref.read(isReorderModeProvider.notifier).set(true);
                    return;
                  }
                  if (value == 'players') {
                    ref.read(isEditPlayersModeProvider.notifier).set(true);
                    return;
                  } else if (value == 'close') {
                    if (!context.mounted) return;
                    ref.read(calculatorProvider.notifier).reset();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const StartScreen()),
                      (_) => false,
                    );
                  } else if (value == 'delete') {
                    final confirm = await showConfirmDialog(
                      context,
                      title: 'Spel verwijderen?',
                      contentText:
                          'Dit spel wordt permanent verwijderd uit de geschiedenis.',
                      confirmLabel: 'Verwijderen',
                      destructive: true,
                    );
                    if (confirm != true) return;
                    if (!context.mounted) return;
                    final sessionId = ref.read(calculatorProvider).sessionId;
                    await ref
                        .read(gameHistoryProvider.notifier)
                        .deleteGame(sessionId);
                    if (!context.mounted) return;
                    ref.read(calculatorProvider.notifier).reset();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const StartScreen()),
                      (_) => false,
                    );
                  }
                },
                itemBuilder: (_) {
                  final canReorder =
                      ref.read(calculatorProvider).history.length >= 2;
                  return [
                    const PopupMenuItem(
                      value: 'players',
                      child: Row(
                        children: [
                          Icon(Symbols.group),
                          SizedBox(width: 12),
                          Text('Spelers bewerken'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reorder',
                      enabled: canReorder,
                      child: const Row(
                        children: [
                          Icon(Symbols.swap_vert),
                          SizedBox(width: 12),
                          Text('Ronde volgorde'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'close',
                      child: Row(
                        children: [
                          Icon(Symbols.stop_circle),
                          SizedBox(width: 12),
                          Text('Spel sluiten'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Symbols.delete),
                          SizedBox(width: 12),
                          Text('Spel verwijderen'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isEditingPlayers
                ? const _EditPlayersPhase(key: ValueKey('editPlayers'))
                : game == null
                ? const _GameSelectionPhase(key: ValueKey('selection'))
                : _GameInputPhase(key: const ValueKey('input'), game: game),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Phase 1 — Game selection
// =============================================================================

class _GameSelectionPhase extends ConsumerWidget {
  const _GameSelectionPhase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only the slices we need: the visible game tiles depend on which
    // games have been played + the current chooser, NOT on whatever the user
    // is typing in `state.input` (we left this phase before that anyway, but
    // a stale subscription would still keep this widget rebuilding when
    // returning here after a round).
    final history = ref.watch(
      calculatorProvider.select((s) => s.history),
    );
    final chooserIndex = ref.watch(
      calculatorProvider.select((s) => s.chooserIndex),
    );
    final isReordering = ref.watch(isReorderModeProvider);
    final playedIds = history.map((r) => r.game.id).toSet();

    final isFinished = history.length >= 12;

    final positiveGames = <MiniGame>[];
    final negativeGames = <MiniGame>[];
    for (final g in allGames) {
      if (playedIds.contains(g.id)) continue;
      if (g.category == GameCategory.positive) {
        positiveGames.add(g);
      } else {
        negativeGames.add(g);
      }
    }

    // Quota counts for the current chooser — computed once instead of
    // re-derived per tile via select().
    var negCount = 0;
    var posCount = 0;
    for (final r in history) {
      if (r.chooserIndex != chooserIndex) continue;
      if (r.game.category == GameCategory.negative) {
        negCount++;
      } else {
        posCount++;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!isReordering) ...[
          const _RoundInfoBanner(),
          const SizedBox(height: 8),
          const _ScoreboardCard(),
          if (isFinished) ...[
            const SizedBox(height: 12),
            const Center(child: _NewGameSamePlayersButton()),
          ],
        ],
        if (!isReordering && !isFinished && negativeGames.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Negatieve spellen',
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          for (final game in negativeGames)
            _GameTile(game: game, negCount: negCount, posCount: posCount),
        ],
        if (!isReordering && !isFinished && positiveGames.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Positieve spellen',
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          for (final game in positiveGames)
            _GameTile(game: game, negCount: negCount, posCount: posCount),
        ],
        const SizedBox(height: 20),
        const _HistoryList(),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: color, letterSpacing: 0.5),
    );
  }
}

class _GameTile extends ConsumerWidget {
  const _GameTile({
    required this.game,
    required this.negCount,
    required this.posCount,
  });

  final MiniGame game;
  final int negCount;
  final int posCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = game.category == GameCategory.positive;
    final accentColor = isPositive ? cs.primary : cs.error;

    final pendingGameId = ref.watch(
      calculatorProvider.select((s) => s.pendingGame?.id),
    );
    final isPending = pendingGameId == game.id;
    final isPendingBlocked = pendingGameId != null && !isPending;

    final isQuotaDisabled =
        (game.category == GameCategory.negative && negCount >= 2) ||
        (game.category == GameCategory.positive && posCount >= 1);

    final isDisabled = (isPendingBlocked || isQuotaDisabled) && !isPending;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: GameAvatar(game: game, radius: 22, disabled: isDisabled),
        title: Text(
          game.name,
          style: TextStyle(
            color: isDisabled ? cs.onSurface.withAlpha(60) : null,
          ),
        ),
        subtitle: Text(
          isPending
              ? 'Niet afgerond  ·  tik om verder te gaan'
              : isPositive
              ? 'Positief  ·  +${game.totalPoints} punten totaal'
              : 'Negatief  ·  ${game.totalPoints} punten totaal',
          style: TextStyle(
            color: isDisabled ? cs.onSurface.withAlpha(60) : accentColor,
          ),
        ),
        trailing: isPending
            ? Icon(Symbols.hourglass_top, color: cs.tertiary)
            : Icon(
                Symbols.chevron_right,
                color: isDisabled ? cs.onSurface.withAlpha(60) : null,
              ),
        onTap: () async {
          final state = ref.read(calculatorProvider);
          // Pending game tile — resume directly.
          if (isPending) {
            ref.read(calculatorProvider.notifier).selectGame(game);
            return;
          }
          // Other games are blocked while a pending game exists.
          if (state.hasPendingGame) {
            await showInfoDialog(
              context,
              title: 'Ronde niet afgerond',
              contentText:
                  '${state.pendingGame!.name} is nog niet afgerond. '
                  'Maak dat spel eerst af.',
            );
            return;
          }
          // Quota-disabled games show a warning with an override option.
          if (isQuotaDisabled) {
            final chooserName = state.playerNames[state.chooserIndex];
            final proceed = await showConfirmDialog(
              context,
              title: 'Limiet overschreden',
              contentText: game.category == GameCategory.negative
                  ? '$chooserName heeft al 2 negatieve spellen gekozen.'
                  : '$chooserName heeft al 1 positief spel gekozen.',
              confirmLabel: 'Toch doorgaan',
            );
            if (!context.mounted) return;
            if (proceed != true) return;
          }
          ref.read(calculatorProvider.notifier).selectGame(game);
        },
      ),
    );
  }
}

// =============================================================================
// Phase 2 — Game input, doubles, result
// =============================================================================

class _GameInputPhase extends ConsumerWidget {
  const _GameInputPhase({super.key, required this.game});

  final MiniGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // NOTE: this widget intentionally does NOT call `ref.watch(calculatorProvider)`.
    // Each section below watches only the slice of state it actually needs, so
    // typing in the input form (which mutates `state.input` 60+ times per
    // numeric stepper hold) does not rebuild the doubles card, the header,
    // or the chooser selector.
    final notifier = ref.read(calculatorProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final isPositive = game.category == GameCategory.positive;
    final accentColor = isPositive ? cs.primary : cs.error;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // --- Game header ---
        _GameInputHeader(
          game: game,
          isPositive: isPositive,
          accentColor: accentColor,
        ),
        const SizedBox(height: 20),

        // --- Chooser selector ---
        Consumer(
          builder: (context, ref, _) {
            final (playerNames, chooserIndex, dealerIndex) = ref.watch(
              calculatorProvider.select(
                (s) => (s.playerNames, s.chooserIndex, s.dealerIndex),
              ),
            );
            return _ChooserSelector(
              playerNames: playerNames,
              chooserIndex: chooserIndex,
              defaultChooserIndex: (dealerIndex + 1) % 4,
            );
          },
        ),
        const SizedBox(height: 12),

        // --- Doubles picker ---
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dubbels', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Consumer(
                  builder: (context, ref, _) {
                    final (playerNames, chooserIndex, doubles) = ref.watch(
                      calculatorProvider.select(
                        (s) => (s.playerNames, s.chooserIndex, s.doubles),
                      ),
                    );
                    return DoublesPicker(
                      playerNames: playerNames,
                      chooserIndex: chooserIndex,
                      doubles: doubles,
                      onChanged: notifier.updateDoubles,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // --- Input form ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resultaat',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Consumer(
                  builder: (context, ref, _) {
                    final (playerNames, input) = ref.watch(
                      calculatorProvider.select(
                        (s) => (s.playerNames, s.input),
                      ),
                    );
                    return GameInputForm(
                      game: game,
                      playerNames: playerNames,
                      input: input,
                      onInputChanged: notifier.updateInput,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // --- Result (auto-calculated) ---
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, _) {
            final (result, partialResult, doubles, chooserIndex, playerNames) =
                ref.watch(
              calculatorProvider.select(
                (s) => (
                  s.result,
                  s.partialResult,
                  s.doubles,
                  s.chooserIndex,
                  s.playerNames,
                ),
              ),
            );
            return result != null
                ? ScoreResultView(
                    result: result,
                    game: game,
                    playerNames: playerNames,
                    doubles: doubles,
                    chooserIndex: chooserIndex,
                  )
                : ScoreResultView(
                    result:
                        partialResult ??
                        const ScoreResult(scores: {0: 0, 1: 0, 2: 0, 3: 0}),
                    game: game,
                    playerNames: playerNames,
                    doubles: doubles,
                    chooserIndex: chooserIndex,
                    isPartial: true,
                  );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Game-name + chooser/dealer header for [_GameInputPhase].
///
/// Watches only the player names + chooser/dealer indices so it doesn't
/// rebuild when the user types into the input form.
class _GameInputHeader extends ConsumerWidget {
  const _GameInputHeader({
    required this.game,
    required this.isPositive,
    required this.accentColor,
  });

  final MiniGame game;
  final bool isPositive;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (playerNames, chooserIndex, dealerIndex) = ref.watch(
      calculatorProvider.select(
        (s) => (s.playerNames, s.chooserIndex, s.dealerIndex),
      ),
    );

    return Row(
      children: [
        GameAvatar(game: game, radius: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.name, style: tt.titleLarge),
              Text(
                isPositive
                    ? 'Positief  ·  +${game.totalPoints} punten totaal'
                    : 'Negatief  ·  ${game.totalPoints} punten totaal',
                style: tt.bodyMedium?.copyWith(color: accentColor),
              ),
              const SizedBox(height: 2),
              Text(
                'Kiezer: ${playerNames[chooserIndex]}  ·  '
                'Deler (eerste kaart): ${playerNames[dealerIndex]}',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Scoreboard — cumulative totals per player
// =============================================================================

class _ScoreboardCard extends ConsumerWidget {
  const _ScoreboardCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calculatorProvider);
    if (state.history.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isFinished = state.history.length >= 12;

    // Sum scores per player across all completed rounds.
    final totals = List<int>.filled(playerCount, 0);
    for (final record in state.history) {
      for (int i = 0; i < playerCount; i++) {
        totals[i] += record.result.scores[i] ?? 0;
      }
    }

    // Winner indices (highest score, may be shared).
    final best = totals.reduce((a, b) => a > b ? a : b);
    final winners = isFinished
        ? [
            for (int i = 0; i < playerCount; i++)
              if (totals[i] == best) i,
          ]
        : <int>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isFinished) ...[
                  Icon(Symbols.emoji_events, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  isFinished ? 'Eindstand' : 'Tussenstand',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (state.updatedAt != null)
                  Text(
                    formatDate(state.updatedAt!),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int i = 0; i < playerCount; i++)
                  Expanded(
                    child: Column(
                      children: [
                        if (isFinished && winners.contains(i))
                          Icon(Symbols.emoji_events, size: 14, color: cs.primary)
                        else
                          const SizedBox(height: 14),
                        Text(
                          state.playerNames[i],
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          totals[i] > 0 ? '+${totals[i]}' : '${totals[i]}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scoreColor(totals[i], cs),
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewGameSamePlayersButton extends ConsumerWidget {
  const _NewGameSamePlayersButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      icon: const Icon(Symbols.replay),
      label: const Text('Nieuw spel met dezelfde spelers'),
      onPressed: () {
        final state = ref.read(calculatorProvider);
        final names = List<String>.from(state.playerNames);
        final notifier = ref.read(calculatorProvider.notifier);
        notifier.reset();
        notifier.setAllPlayerNames(names);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SetupScreen()),
        );
      },
    );
  }
}

// =============================================================================
// History list — compact log of completed rounds
// =============================================================================

class _HistoryList extends ConsumerWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow subscription: rebuild only when one of these slices changes,
    // not on every input keystroke / chooser tap / etc. The list of player
    // names is referenced by every row but stays constant during gameplay.
    final (history, playerNames, hasPendingGame, pendingGameName) = ref.watch(
      calculatorProvider.select(
        (s) => (
          s.history,
          s.playerNames,
          s.hasPendingGame,
          s.pendingGame?.name,
        ),
      ),
    );
    if (history.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(calculatorProvider.notifier);
    final isReordering = ref.watch(isReorderModeProvider);

    // In reorder mode: use a ReorderableListView without edit buttons.
    if (isReordering) {
      // history is chronological (round 1 first); show in that order for drag.
      final rounds = history;
      return RepaintBoundary(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Symbols.swap_vert, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Ronde volgorde',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // ReorderableListView needs a fixed height or shrinkWrap.
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: rounds.length,
                  onReorder: notifier.reorderRounds,
                  itemBuilder: (ctx, i) {
                    final record = rounds[i];
                    return Material(
                      key: ValueKey(record.roundNumber),
                      color: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                DragHandle(index: i),
                                Expanded(
                                  child: _RoundRowHeader(
                                    record: record,
                                    playerNames: playerNames,
                                    cs: cs,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }

    // Normal mode: reversed (most recent first), with edit buttons.
    final lastRoundNumber = history.last.roundNumber;
    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gespeelde rondes',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final record in history.reversed) ...[
                const Divider(height: 16),
                _HistoryRow(
                  record: record,
                  playerNames: playerNames,
                  cs: cs,
                  notifier: notifier,
                  showDelete: record.roundNumber == lastRoundNumber &&
                      !hasPendingGame,
                  hasPendingGame: hasPendingGame,
                  pendingGameName: pendingGameName,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single row in [_HistoryList].
///
/// Extracted as a const-friendly widget so iterating over reversed history
/// produces independent subtrees that won't all rebuild together.
///
/// The trailing column always reserves the same vertical space as a row
/// with both edit + delete IconButtons. For non-last rows we render a
/// [SizedBox] placeholder of [kMinInteractiveDimension] so the edit icons
/// stay aligned across rows without paying for an offscreen [IconButton]
/// (which is what the previous `Visibility(maintainState: true)` setup did).
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.record,
    required this.playerNames,
    required this.cs,
    required this.notifier,
    required this.showDelete,
    required this.hasPendingGame,
    required this.pendingGameName,
  });

  final RoundRecord record;
  final List<String> playerNames;
  final ColorScheme cs;
  final CalculatorNotifier notifier;
  final bool showDelete;
  final bool hasPendingGame;
  final String? pendingGameName;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Round + game
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoundRowHeader(
                record: record,
                playerNames: playerNames,
                cs: cs,
              ),
              if (record.doubles.hasAnyDouble)
                DoublesChips(
                  doubles: record.doubles,
                  names: playerNames,
                  chooserIndex: record.chooserIndex,
                ),
            ],
          ),
        ),
        // Per-player deltas — names right-aligned, scores right-aligned.
        // We keep IntrinsicWidth here on purpose: a fixed score-column
        // width would either crowd extreme scores or waste horizontal
        // space for normal scores. With at most 12 rounds in a Bonken
        // game the extra layout pass per row is negligible.
        IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < playerCount; i++)
                    Text(
                      '${playerNames[i]}:',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < playerCount; i++)
                    Text(
                      formatScore(record.result.scores[i] ?? 0),
                      style: tt.bodyMedium?.copyWith(
                        color: scoreColor(record.result.scores[i] ?? 0, cs),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Edit + (optional) delete buttons. Non-last rows still reserve
        // the delete-button vertical space so all edit icons line up.
        Column(
          children: [
            IconButton(
              icon: const Icon(Symbols.edit, size: 18),
              tooltip: 'Wijzigen',
              visualDensity: VisualDensity.compact,
              onPressed: () => notifier.restoreRound(record),
            ),
            if (showDelete)
              IconButton(
                icon: const Icon(Symbols.delete, size: 18),
                tooltip: 'Ronde verwijderen',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  if (hasPendingGame) {
                    await showInfoDialog(
                      context,
                      title: 'Kan ronde niet verwijderen',
                      contentText:
                          '${pendingGameName ?? ''} is nog niet afgerond. '
                          'Maak dat spel eerst af voordat je de laatste ronde verwijdert.',
                    );
                    return;
                  }
                  if (!context.mounted) return;
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Ronde verwijderen?',
                    contentText:
                        'Ronde ${record.roundNumber} (${record.game.name}) '
                        'wordt permanent verwijderd.',
                    confirmLabel: 'Verwijderen',
                    destructive: true,
                  );
                  if (confirm != true) return;
                  notifier.deleteLastRound();
                },
              )
            else
              // Placeholder so the edit icon stays aligned with rows that
              // do show a delete button. Same height as a compact IconButton.
              const SizedBox(height: kMinInteractiveDimension),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Chooser selector widget — used inside _GameInputPhase
// =============================================================================

class _ChooserSelector extends ConsumerWidget {
  const _ChooserSelector({
    required this.playerNames,
    required this.chooserIndex,
    required this.defaultChooserIndex,
  });

  final List<String> playerNames;
  final int chooserIndex;
  final int defaultChooserIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wie koos dit spel?',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: chooserIndex,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (int i = 0; i < playerCount; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      playerNames[i],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (selected) async {
                if (selected == null || selected == chooserIndex) return;
                if (selected == defaultChooserIndex) {
                  notifier.setChooser(selected);
                  return;
                }
                final expectedName = playerNames[defaultChooserIndex];
                final selectedName = playerNames[selected];
                if (!context.mounted) return;
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Kiezer wijzigen',
                  contentText:
                      '$expectedName is aan de beurt om te kiezen. '
                      'Wil je toch $selectedName als kiezer instellen?',
                  confirmLabel: 'Instellen',
                );
                if (confirm == true) notifier.setChooser(selected);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Round info banner — shown in the game selection phase
// =============================================================================

class _RoundInfoBanner extends ConsumerWidget {
  const _RoundInfoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calculatorProvider);
    final cs = Theme.of(context).colorScheme;
    final round = state.roundNumber;
    final dealerName = state.playerNames[state.dealerIndex];
    final chooserName = state.playerNames[(state.dealerIndex + 1) % 4];

    // Hide once all 12 rounds are done.
    if (state.history.length >= 12) return const SizedBox.shrink();

    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Symbols.info, size: 18, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ronde $round van 12',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Deler: $dealerName  ·  Kiezer: $chooserName',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Edit players phase — full-page form shown in place of the game selection list
// =============================================================================

class _EditPlayersPhase extends ConsumerStatefulWidget {
  const _EditPlayersPhase({super.key});

  @override
  ConsumerState<_EditPlayersPhase> createState() => _EditPlayersPhaseState();
}

class _EditPlayersPhaseState extends ConsumerState<_EditPlayersPhase> {
  // Short labels shown both in-line under their respective fields and
  // listed in the confirmation dialog when saving while a game is in progress.
  static const _playerOrderShortWarning =
      'De volgorde van de spelers wordt aangepast.';
  static const _dealerShortWarning =
      'De deler van de eerste ronde wordt aangepast.';
  static const _inProgressEffectExplanation =
      'Dit heeft alleen effect bij invoer van een nieuwe ronde. Van reeds '
      'ingevoerde rondes (ook die van de eerste ronde) en rondes die al '
      'gestart zijn worden de kiezer, dubbels en scores niet van aangepast.';

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  // Snapshot of the original controller order, used to detect player reorders
  // by identity (text edits do not affect this).
  late final List<TextEditingController> _originalControllerOrder;
  late int _dealerIndex;
  late final bool _gameInProgress;
  late final List<String> _originalNames;
  late final int _originalDealerIndex;

  @override
  void initState() {
    super.initState();
    final state = ref.read(calculatorProvider);
    _dealerIndex = state.dealerIndex;
    _originalDealerIndex = state.dealerIndex;
    _gameInProgress = state.history.isNotEmpty || state.hasPendingGame;
    _originalNames = List.unmodifiable(state.playerNames);
    _controllers = [
      for (final name in state.playerNames) TextEditingController(text: name),
    ];
    _originalControllerOrder = List.unmodifiable(_controllers);
    _focusNodes = List.generate(playerCount, (_) => FocusNode());
    for (final c in _controllers) {
      c.addListener(_onFormChanged);
    }
    // Initialise providers to reflect starting state.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateProviders());
  }

  void _onFormChanged() => _updateProviders();

  bool get _orderChanged =>
      !listEquals(_controllers, _originalControllerOrder);

  void _updateProviders() {
    if (!mounted) return;
    final trimmed = _controllers.map((c) => c.text.trim()).toList();
    final lower = trimmed.map((n) => n.toLowerCase()).toList();
    final canSave =
        trimmed.every((n) => n.isNotEmpty) && lower.toSet().length == 4;
    final hasChanges =
        _controllers.indexed.any(
          (e) => e.$2.text.trim() != _originalNames[e.$1],
        ) ||
        _dealerIndex != _originalDealerIndex;
    // PlayerListField (duplicate warning) and DealerDropdownField
    // (player-name labels) are wrapped in [ListenableBuilder]s in [build]
    // and rebuild themselves from the controller listeners — no setState
    // needed here, which avoids rebuilding the entire phase on every
    // keystroke (cards, suggestions watch, ReorderableListView, …).
    ref.read(_canSavePlayersProvider.notifier).set(canSave);
    ref.read(_hasPlayersChangesProvider.notifier).set(hasChanges);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(_onFormChanged);
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _handleFieldSubmitted(int index) => handlePlayerFieldSubmitted(
    index: index,
    controllers: _controllers,
    focusNodes: _focusNodes,
  );

  void _onReorder(int oldIndex, int newIndex) {
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= playerCount) target = playerCount - 1;
    if (target == oldIndex) return;

    setState(() {
      final c = _controllers.removeAt(oldIndex);
      _controllers.insert(target, c);
      final f = _focusNodes.removeAt(oldIndex);
      _focusNodes.insert(target, f);
      // Keep _dealerIndex pointing at the same person.
      _dealerIndex = adjustIndexAfterReorder(oldIndex, target, _dealerIndex);
    });
    _updateProviders();
  }

  Future<void> _save() async {
    if (_controllers.any((c) => c.text.trim().isEmpty)) return;
    final dealerChanged = _dealerIndex != _originalDealerIndex;
    final orderChanged = _orderChanged;
    if (_gameInProgress && (dealerChanged || orderChanged)) {
      final bodyStyle = Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: Colors.amber);
      final confirm = await showConfirmDialog(
        context,
        title: 'Lopend spel wijzigen',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (orderChanged)
              _AmberWarningRow(
                text: _playerOrderShortWarning,
                style: bodyStyle,
              ),
            if (orderChanged && dealerChanged) const SizedBox(height: 6),
            if (dealerChanged)
              _AmberWarningRow(
                text: _dealerShortWarning,
                style: bodyStyle,
              ),
            const SizedBox(height: 10),
            Text(_inProgressEffectExplanation, style: bodyStyle),
          ],
        ),
        confirmLabel: 'Wijzigen',
      );
      if (confirm != true) return;
      if (!mounted) return;
    }
    final notifier = ref.read(calculatorProvider.notifier);
    for (int i = 0; i < playerCount; i++) {
      notifier.setPlayerName(i, _controllers[i].text.trim());
    }
    if (dealerChanged) {
      notifier.setDealer(_dealerIndex);
    }
    ref.read(isEditPlayersModeProvider.notifier).set(false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_editPlayersSaveTriggerProvider, (_, _) => _save());

    final suggestions = ref
        .watch(gameHistoryProvider.notifier)
        .playerNameSuggestions;
    final orderChanged = _orderChanged;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spelers', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Sleep om de volgorde te wijzigen.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: Listenable.merge(_controllers),
                  builder: (context, _) => PlayerListField(
                    controllers: _controllers,
                    focusNodes: _focusNodes,
                    suggestions: suggestions,
                    onReorder: _onReorder,
                    onSubmitted: _handleFieldSubmitted,
                  ),
                ),
                if (_gameInProgress && orderChanged) ...[
                  const SizedBox(height: 12),
                  _AmberWarningRow(
                    text: _playerOrderShortWarning,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.amber),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deler eerste ronde',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: Listenable.merge(_controllers),
                  builder: (context, _) => DealerDropdownField(
                    controllers: _controllers,
                    value: _dealerIndex,
                    onChanged: (v) {
                      setState(() => _dealerIndex = v);
                      _updateProviders();
                    },
                  ),
                ),
                if (_gameInProgress &&
                    _dealerIndex != _originalDealerIndex) ...[
                  const SizedBox(height: 8),
                  _AmberWarningRow(
                    text: _dealerShortWarning,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.amber),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact "Ronde N — game name / chooser name" row used in both the regular
/// and reorder modes of [_HistoryList].
class _RoundRowHeader extends StatelessWidget {
  const _RoundRowHeader({
    required this.record,
    required this.playerNames,
    required this.cs,
  });

  final RoundRecord record;
  final List<String> playerNames;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ronde ${record.roundNumber} — ${record.game.name}',
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          playerNames[record.chooserIndex],
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Compact row with an amber warning icon and amber text.
class _AmberWarningRow extends StatelessWidget {
  const _AmberWarningRow({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Symbols.warning_amber, size: 16, color: Colors.amber),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// Circular avatar showing a mini-game's symbol with its accent color.
class GameAvatar extends StatelessWidget {
  const GameAvatar({
    required this.game,
    required this.radius,
    this.disabled = false,
    super.key,
  });

  final MiniGame game;
  final double radius;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = game.category == GameCategory.positive;
    final accentColor = isPositive ? cs.primary : cs.error;
    final symbolColor = _gameColors[game.id] ?? accentColor;
    final symbol = _gameSymbols[game.id] ?? '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: symbolColor.withAlpha(disabled ? 15 : 30),
      child: _GameSymbol(
        symbol: symbol,
        gameId: game.id,
        color: disabled ? cs.onSurface.withAlpha(60) : symbolColor,
        fontSize: 16,
      ),
    );
  }
}

/// Renders a game symbol. The four suit-based games (and the games derived
/// from them — `kingOfHearts`, `heartPoints`) are rendered with vector
/// [CupertinoIcons] suit glyphs so they look monochrome and consistent on all
/// platforms (Android otherwise renders the Unicode suit characters as
/// colored emoji, even with the VS15 text selector). All other games fall
/// back to the textual [symbol].
class _GameSymbol extends StatelessWidget {
  const _GameSymbol({
    required this.symbol,
    required this.gameId,
    required this.color,
    required this.fontSize,
  });

  final String symbol;
  final String gameId;
  final Color color;
  final double fontSize;

  static const _suitIcons = {
    'clubs': CupertinoIcons.suit_club_fill,
    'diamonds': CupertinoIcons.suit_diamond_fill,
    'hearts': CupertinoIcons.suit_heart_fill,
    'spades': CupertinoIcons.suit_spade_fill,
  };

  Widget _suitIcon(IconData icon, double size) =>
      Icon(icon, size: size, color: color);

  @override
  Widget build(BuildContext context) {
    final suit = _suitIcons[gameId];
    if (suit != null) {
      return _suitIcon(suit, fontSize);
    }
    if (gameId == 'kingOfHearts') {
      // Render heart + 'H' as a single text run so the icon participates in
      // the same baseline/line-box layout as the letter.  This keeps them
      // aligned much more reliably than two side-by-side widgets, which
      // suffer from sub-pixel rounding differences (especially at low zoom
      // levels in the browser).  The Cupertino suit glyph is slightly
      // smaller than its bounding box, so scale it up a touch to match the
      // cap height of the 'H'.  We also apply the user's text scale factor
      // to the icon so the heart grows proportionally with the 'H' when the
      // OS font size setting is non-default.
      final textScale = MediaQuery.textScalerOf(context).scale(fontSize);
      final iconSize = textScale * 1.1;
      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                CupertinoIcons.suit_heart_fill,
                size: iconSize,
                color: color,
              ),
            ),
            TextSpan(
              text: 'H',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
                height: 1.0,
              ),
            ),
          ],
        ),
      );
    }
    if (gameId == 'heartPoints') {
      // Match the heart sizing used for kingOfHearts so the two heart-based
      // game icons look visually consistent under any text scale setting.
      final iconSize = MediaQuery.textScalerOf(context).scale(fontSize) * 1.1;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _suitIcon(CupertinoIcons.suit_heart_fill, iconSize),
          _suitIcon(CupertinoIcons.suit_heart_fill, iconSize),
        ],
      );
    }
    return Text(
      symbol,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: fontSize,
      ),
    );
  }
}
