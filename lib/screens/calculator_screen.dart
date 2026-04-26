import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/double_matrix.dart';
import '../models/games/game_catalog.dart';
import '../models/mini_game.dart';
import '../models/round_record.dart';
import '../models/score_result.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/dialogs.dart';
import '../widgets/doubles_picker.dart';
import '../widgets/game_input/game_input_form.dart';
import '../widgets/score_result_view.dart';
import 'start_screen.dart';

/// Scoped to the CalculatorScreen lifetime — true while reorder mode is active.
class _IsReorderModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final isReorderModeProvider = NotifierProvider<_IsReorderModeNotifier, bool>(
  _IsReorderModeNotifier.new,
);

/// Snapshot of history order taken when entering reorder mode, used for Cancel.
class _ReorderSnapshotNotifier extends Notifier<List<RoundRecord>> {
  @override
  List<RoundRecord> build() => const [];
  void set(List<RoundRecord> snapshot) => state = snapshot;
}

final reorderSnapshotProvider =
    NotifierProvider<_ReorderSnapshotNotifier, List<RoundRecord>>(
      _ReorderSnapshotNotifier.new,
    );

/// True while the edit-players page is shown in place of the game list.
class _IsEditPlayersModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final isEditPlayersModeProvider =
    NotifierProvider<_IsEditPlayersModeNotifier, bool>(
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
    NotifierProvider<_EditPlayersSaveTriggerNotifier, int>(
      _EditPlayersSaveTriggerNotifier.new,
    );

/// True when all player name fields are non-empty (save is allowed).
class _CanSavePlayersNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool value) => state = value;
}

final _canSavePlayersProvider = NotifierProvider<_CanSavePlayersNotifier, bool>(
  _CanSavePlayersNotifier.new,
);

/// True when the edit-players form has unsaved changes.
class _HasPlayersChangesNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final _hasPlayersChangesProvider =
    NotifierProvider<_HasPlayersChangesNotifier, bool>(
      _HasPlayersChangesNotifier.new,
    );

// Game symbols displayed next to each game name in the selection list.
const _gameSymbols = {
  'clubs': '♣',
  'diamonds': '♦',
  'hearts': '♥',
  'spades': '♠',
  'noTrump': 'SA',
  'kingOfHearts': '♥H',
  'kingsAndJacks': 'H/B',
  'queens': 'V',
  'duck': '▼',
  'heartPoints': '♥♥',
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
        final confirm = await showConfirmDialog(
          context,
          title: isEditing ? 'Wijzigingen verwerpen' : 'Invoer verwerpen',
          contentText: isEditing
              ? 'Je aanpassingen gaan verloren.'
              : 'Je ingevoerde gegevens gaan verloren.',
          confirmLabel: 'Verwerpen',
          destructive: true,
        );
        if (confirm != true) return;
      }
      cancelInputPhase();
    }

    Future<void> saveOrConfirmBack() async {
      final state = ref.read(calculatorProvider);
      if (state.isEditingExistingRound) {
        // Back while editing = discard path, same as Verwerpen.
        if (state.hasActiveChanges) {
          if (!context.mounted) return;
          final confirm = await showConfirmDialog(
            context,
            title: 'Wijzigingen niet opgeslagen',
            contentText: 'Je aanpassingen gaan verloren.',
            confirmLabel: 'Verwerpen',
            destructive: true,
          );
          if (confirm != true) return;
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
        final confirm = await showConfirmDialog(
          context,
          title: 'Wijzigingen verwerpen',
          contentText: 'Je aanpassingen gaan verloren.',
          confirmLabel: 'Verwerpen',
          destructive: true,
        );
        if (confirm != true) return;
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
        final confirm = await showConfirmDialog(
          context,
          title: 'Wijzigingen verwerpen',
          contentText:
              'Je aanpassingen aan de volgorde worden niet opgeslagen.',
          confirmLabel: 'Verwerpen',
          destructive: true,
        );
        if (confirm != true) return;
      }
      ref
          .read(calculatorProvider.notifier)
          .restoreHistory(ref.read(reorderSnapshotProvider));
      ref.read(isReorderModeProvider.notifier).set(false);
    }

    return PopScope(
      // Allow native back when no game is selected (pops to HomeScreen).
      // When a game is selected, intercept back to deselect instead.
      // While reordering or editing players, intercept back to cancel.
      canPop: game == null && !isReordering && !isEditingPlayers,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (isEditingPlayers) {
            confirmAndCancelPlayers();
          } else if (isReordering) {
            confirmAndCancelReorder();
          } else if (game != null) {
            saveOrConfirmBack();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bonken'),
          leading: game != null || isReordering || isEditingPlayers
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Verwerpen',
                  onPressed: () {
                    if (isEditingPlayers) {
                      confirmAndCancelPlayers();
                    } else if (isReordering) {
                      confirmAndCancelReorder();
                    } else {
                      saveOrConfirmBack();
                    }
                  },
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
                          Icon(Icons.people_outline),
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
                          Icon(Icons.swap_vert),
                          SizedBox(width: 12),
                          Text('Ronde volgorde'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'close',
                      child: Row(
                        children: [
                          Icon(Icons.stop_circle_outlined),
                          SizedBox(width: 12),
                          Text('Spel sluiten'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline),
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
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isEditingPlayers
              ? const _EditPlayersPhase(key: ValueKey('editPlayers'))
              : game == null
              ? const _GameSelectionPhase(key: ValueKey('selection'))
              : _GameInputPhase(key: const ValueKey('input'), game: game),
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
    final state = ref.watch(calculatorProvider);
    final isReordering = ref.watch(isReorderModeProvider);
    final history = state.history;
    final playedIds = history.map((r) => r.game.id).toSet();

    final isFinished = history.length >= 12;

    final positiveGames = allGames
        .where(
          (g) =>
              g.category == GameCategory.positive && !playedIds.contains(g.id),
        )
        .toList();
    final negativeGames = allGames
        .where(
          (g) =>
              g.category == GameCategory.negative && !playedIds.contains(g.id),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!isReordering) ...[
          const _RoundInfoBanner(),
          const SizedBox(height: 8),
          const _ScoreboardCard(),
        ],
        if (!isReordering && !isFinished && negativeGames.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Negatieve spellen',
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          for (final game in negativeGames) _GameTile(game: game),
        ],
        if (!isReordering && !isFinished && positiveGames.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Positieve spellen',
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          for (final game in positiveGames) _GameTile(game: game),
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
  const _GameTile({required this.game});

  final MiniGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = game.category == GameCategory.positive;
    final accentColor = isPositive ? cs.primary : cs.error;
    final symbolColor = _gameColors[game.id] ?? accentColor;
    final symbol = _gameSymbols[game.id] ?? '?';

    final pendingGameId = ref.watch(
      calculatorProvider.select((s) => s.pendingGame?.id),
    );
    final isPending = pendingGameId == game.id;
    final isPendingBlocked = pendingGameId != null && !isPending;

    // Quota check — compute at build time so the tile can be visually disabled.
    final chooserIndex = ref.watch(
      calculatorProvider.select((s) => s.chooserIndex),
    );
    final chooserRounds = ref.watch(
      calculatorProvider.select(
        (s) => s.history.where((r) => r.chooserIndex == chooserIndex).toList(),
      ),
    );
    final negCount = chooserRounds
        .where((r) => r.game.category == GameCategory.negative)
        .length;
    final posCount = chooserRounds
        .where((r) => r.game.category == GameCategory.positive)
        .length;
    final isQuotaDisabled =
        (game.category == GameCategory.negative && negCount >= 2) ||
        (game.category == GameCategory.positive && posCount >= 1);

    final isDisabled = (isPendingBlocked || isQuotaDisabled) && !isPending;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: symbolColor.withAlpha(isDisabled ? 15 : 30),
          child: _GameSymbol(
            symbol: symbol,
            gameId: game.id,
            color: isDisabled ? cs.onSurface.withAlpha(60) : symbolColor,
            fontSize: 16,
          ),
        ),
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
            ? Icon(Icons.hourglass_top_rounded, color: cs.tertiary)
            : Icon(
                Icons.chevron_right,
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
            final chooserName = state.playerNames[chooserIndex];
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
    final state = ref.watch(calculatorProvider);
    final notifier = ref.read(calculatorProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    final isPositive = game.category == GameCategory.positive;
    final accentColor = isPositive ? cs.primary : cs.error;
    final symbolColor = _gameColors[game.id] ?? accentColor;
    final symbol = _gameSymbols[game.id] ?? '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // --- Game header ---
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: symbolColor.withAlpha(30),
              child: _GameSymbol(
                symbol: symbol,
                gameId: game.id,
                color: symbolColor,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    isPositive
                        ? 'Positief  ·  +${game.totalPoints} punten totaal'
                        : 'Negatief  ·  ${game.totalPoints} punten totaal',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: accentColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kiezer: ${state.playerNames[state.chooserIndex]}  ·  '
                    'Deler (eerste kaart): ${state.playerNames[state.dealerIndex]}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // --- Chooser selector ---
        _ChooserSelector(
          playerNames: state.playerNames,
          chooserIndex: state.chooserIndex,
          defaultChooserIndex: (state.dealerIndex + 1) % 4,
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
                DoublesPicker(
                  playerNames: state.playerNames,
                  chooserIndex: state.chooserIndex,
                  doubles: state.doubles,
                  onChanged: notifier.updateDoubles,
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
                GameInputForm(
                  game: game,
                  playerNames: state.playerNames,
                  input: state.input,
                  onInputChanged: notifier.updateInput,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // --- Result (auto-calculated) ---
        const SizedBox(height: 16),
        if (state.result != null)
          ScoreResultView(
            result: state.result!,
            game: game,
            playerNames: state.playerNames,
          )
        else
          ScoreResultView(
            result:
                state.partialResult ??
                ScoreResult(scores: {0: 0, 1: 0, 2: 0, 3: 0}),
            game: game,
            playerNames: state.playerNames,
            isPartial: true,
          ),
        const SizedBox(height: 24),
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
                  Icon(Icons.emoji_events, size: 18, color: cs.primary),
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
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                          Icon(Icons.emoji_events, size: 14, color: cs.primary)
                        else
                          const SizedBox(height: 14),
                        Text(
                          state.playerNames[i],
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
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

// =============================================================================
// History list — compact log of completed rounds
// =============================================================================

/// A compact row of doubles chips for a single round, e.g.
/// [primaryChip "A × B"] [tertiaryChip "C ×× D"]
/// Returns null when there are no active doubles.
class _DoublesChips extends StatelessWidget {
  const _DoublesChips({required this.doubles, required this.names});

  final DoubleMatrix doubles;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    const pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final redoubleBg = redoubleContainer(cs, brightness);
    final onRedoubleBg = onRedoubleContainer(cs, brightness);
    final chips = <Widget>[];

    for (final (a, b) in pairs) {
      final state = doubles.stateFor(a, b);
      if (state == DoubleState.none) continue;
      final initiator = doubles.initiatorFor(a, b) ?? a;
      final other = initiator == a ? b : a;
      final label = state == DoubleState.redoubled
          ? '${names[initiator]} ×× ${names[other]}'
          : '${names[initiator]} × ${names[other]}';
      final bg = state == DoubleState.redoubled
          ? redoubleBg
          : cs.primaryContainer;
      final fg = state == DoubleState.redoubled
          ? onRedoubleBg
          : cs.onPrimaryContainer;
      if (chips.isNotEmpty) chips.add(const SizedBox(width: 4));
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(spacing: 4, runSpacing: 4, children: chips),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calculatorProvider);
    if (state.history.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(calculatorProvider.notifier);
    final isReordering = ref.watch(isReorderModeProvider);

    // In reorder mode: use a ReorderableListView without edit buttons.
    if (isReordering) {
      // history is chronological (round 1 first); show in that order for drag.
      final rounds = state.history;
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_vert, size: 16, color: cs.primary),
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
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ronde ${record.roundNumber} — ${record.game.name}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Text(
                                      state.playerNames[record.chooserIndex],
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
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
      );
    }

    // Normal mode: reversed (most recent first), with edit buttons.
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gespeelde rondes',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final record in state.history.reversed) ...[
              const Divider(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Round + game
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ronde ${record.roundNumber} — ${record.game.name}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          state.playerNames[record.chooserIndex],
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (record.doubles.hasAnyDouble)
                          _DoublesChips(
                            doubles: record.doubles,
                            names: state.playerNames,
                          ),
                      ],
                    ),
                  ),
                  // Per-player deltas — names right-aligned, scores right-aligned
                  IntrinsicWidth(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (int i = 0; i < playerCount; i++)
                              Text(
                                '${state.playerNames[i]}:',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
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
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: scoreColor(
                                        record.result.scores[i] ?? 0,
                                        cs,
                                      ),
                                    ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Edit button
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Aanpassen',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => notifier.restoreRound(record),
                  ),
                  // Delete button — only visible for the last round.
                  // maintainSize keeps all rows identical in width so that
                  // the edit buttons stay perfectly aligned.
                  Visibility(
                    visible:
                        record.roundNumber == state.history.last.roundNumber &&
                        !state.hasPendingGame,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Ronde verwijderen',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        if (state.hasPendingGame) {
                          await showInfoDialog(
                            context,
                            title: 'Kan ronde niet verwijderen',
                            contentText:
                                '${state.pendingGame!.name} is nog niet afgerond. '
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
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
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
              style: Theme.of(context).textTheme.labelMedium,
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
            Icon(Icons.info_outline, size: 18, color: cs.onSecondaryContainer),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
  late final List<TextEditingController> _controllers;
  late int _dealerIndex;
  late final bool _dealerEnabled;
  late final List<String> _originalNames;
  late final int _originalDealerIndex;
  bool _hasDuplicateNames = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(calculatorProvider);
    _dealerIndex = state.dealerIndex;
    _originalDealerIndex = state.dealerIndex;
    _dealerEnabled = state.history.isEmpty && !state.hasPendingGame;
    _originalNames = List.unmodifiable(state.playerNames);
    _controllers = [
      for (final name in state.playerNames) TextEditingController(text: name),
    ];
    for (final c in _controllers) {
      c.addListener(_onFormChanged);
    }
    // Initialise providers to reflect starting state.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateProviders());
  }

  void _onFormChanged() => _updateProviders();

  void _updateProviders() {
    if (!mounted) return;
    final trimmed = _controllers.map((c) => c.text.trim()).toList();
    final nonEmpty = trimmed.where((n) => n.isNotEmpty).toList();
    final hasDuplicates = nonEmpty.length != nonEmpty.toSet().length;
    final canSave =
        trimmed.every((n) => n.isNotEmpty) && trimmed.toSet().length == 4;
    final hasChanges =
        _controllers.indexed.any(
          (e) => e.$2.text.trim() != _originalNames[e.$1],
        ) ||
        (_dealerEnabled && _dealerIndex != _originalDealerIndex);
    setState(() => _hasDuplicateNames = hasDuplicates);
    ref.read(_canSavePlayersProvider.notifier).set(canSave);
    ref.read(_hasPlayersChangesProvider.notifier).set(hasChanges);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(_onFormChanged);
      c.dispose();
    }
    // Reset providers when leaving.
    ref.read(_canSavePlayersProvider.notifier).set(true);
    ref.read(_hasPlayersChangesProvider.notifier).set(false);
    super.dispose();
  }

  void _save() {
    if (_controllers.any((c) => c.text.trim().isEmpty)) return;
    final notifier = ref.read(calculatorProvider.notifier);
    for (int i = 0; i < playerCount; i++) {
      notifier.setPlayerName(i, _controllers[i].text.trim());
    }
    if (_dealerEnabled) {
      notifier.setDealer(_dealerIndex);
    }
    ref.read(isEditPlayersModeProvider.notifier).set(false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_editPlayersSaveTriggerProvider, (_, _) => _save());

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
                const SizedBox(height: 16),
                for (int i = 0; i < playerCount; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  TextField(
                    controller: _controllers[i],
                    decoration: InputDecoration(
                      labelText: 'Speler ${i + 1}',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ],
                if (_hasDuplicateNames) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Twee spelers hebben dezelfde naam.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
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
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setInnerState) {
                    return DropdownButtonFormField<int>(
                      initialValue: _dealerIndex,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (int i = 0; i < playerCount; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              _controllers[i].text.isNotEmpty
                                  ? _controllers[i].text
                                  : 'Speler ${i + 1}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _dealerEnabled
                          ? (v) {
                              if (v == null) return;
                              setInnerState(() => _dealerIndex = v);
                              _updateProviders();
                            }
                          : null,
                    );
                  },
                ),
                if (!_dealerEnabled) ...[
                  const SizedBox(height: 8),
                  Text(
                    'De deler kan niet meer worden gewijzigd nadat de eerste ronde is gestart.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

/// Renders a game symbol. For 'kingOfHearts' the ♥ is rendered slightly
/// smaller than the H so both characters appear the same visual size.
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

  @override
  Widget build(BuildContext context) {
    if (gameId == 'kingOfHearts') {
      return RichText(
        text: TextSpan(
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
          ),
          children: [
            TextSpan(
              text: '♥',
              style: TextStyle(fontSize: fontSize * 0.93),
            ),
            const TextSpan(text: 'H'),
          ],
        ),
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
