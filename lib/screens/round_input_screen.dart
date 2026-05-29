import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_rules.dart';
import '../models/hearts_variant.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/score_result.dart';
import '../state/calculator_provider.dart';
import '../utils.dart';
import '../widgets/amber_warning_box.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/doubles_picker.dart';
import '../widgets/game_avatar.dart';
import '../widgets/game_input/game_input_form.dart';
import '../widgets/incomplete_form_snackbar.dart';
import '../widgets/score_result_view.dart';

// Confirmation body shown when the user tries to save a round whose score
// fields are not (yet) fully entered.
const _incompleteScoreSavePrompt =
    'De score is nog niet compleet. Wil je toch doorgaan met opslaan?';

/// Standard confirmation dialog used whenever the user is about to abandon
/// unsaved edits. Returns true if the user confirms the discard.
Future<bool> _confirmDiscardChanges(
  BuildContext context, {
  String title = 'Wijzigingen verwerpen',
  String contentText = kDiscardChangesMessage,
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

/// Per-round score input destination.
///
/// Pushed from [GameSelectionPhase] when the user picks (or resumes) a
/// mini-game, and from the history row's "Wijzigen" button when the user
/// re-edits a past round.  Reads/mutates [calculatorProvider] directly.
///
/// Callers MUST set `state.selectedGame` (via `selectGame` / `restoreRound`)
/// before pushing this route; the game is captured once in [initState] and
/// is treated as immutable for the screen's lifetime.  Save / discard
/// handlers clear `selectedGame` *and* call `Navigator.pop` themselves.
class RoundInputScreen extends ConsumerStatefulWidget {
  const RoundInputScreen({super.key});

  @override
  ConsumerState<RoundInputScreen> createState() => _RoundInputScreenState();
}

class _RoundInputScreenState extends ConsumerState<RoundInputScreen> {
  // Captured once at push time — see class doc.  The bang is intentional:
  // pushing without a selected game is a programmer error and should crash
  // loudly rather than silently render nothing.
  late final MiniGame _game = ref.read(calculatorProvider).selectedGame!;

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final isEditing = ref.watch(
      calculatorProvider.select((s) => s.isEditingExistingRound),
    );

    void popIfMounted() {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    void cancelInputPhase() {
      if (isEditing) {
        ref.read(calculatorProvider.notifier).cancelEditRound();
      } else {
        ref.read(calculatorProvider.notifier).discardGame();
      }
      popIfMounted();
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
              ? kDiscardChangesMessage
              : 'Je ingevoerde gegevens gaan verloren.',
        );
        if (!confirmed) return;
      }
      cancelInputPhase();
    }

    Future<void> saveOrConfirmBack() async {
      final state = ref.read(calculatorProvider);

      if (!state.hasActiveChanges) {
        cancelInputPhase();
        return;
      }

      await showInfoDialog(
        context,
        title: state.isEditingExistingRound
            ? 'Scores aangepast'
            : 'Scores ingevoerd',
        contentText: state.isEditingExistingRound
            ? 'Je aanpassingen zijn nog niet opgeslagen. '
                  'Sla de scores op of verwerp ze om terug te gaan.'
            : 'Je ingevoerde scores zijn nog niet opgeslagen. '
                  'Sla de scores op of verwerp ze om terug te gaan.',
      );
    }

    Future<void> saveOrConfirmDone() async {
      final state = ref.read(calculatorProvider);
      if (state.result != null) {
        if (state.hasActiveChanges) {
          if (!context.mounted) return;
          final dispPlayers = state.displayedPlayers;
          final dispChooser = state.displayedChooserIndex;
          final confirm = await showConfirmDialog(
            context,
            title: 'Score',
            content: SingleChildScrollView(
              child: ScoreResultView(
                result: state.result!,
                game: state.selectedGame!,
                players: dispPlayers,
                doubles: state.doubles,
                chooserIndex: dispChooser,
                showHeader: false,
              ),
            ),
            confirmLabel: 'Opslaan',
          );
          if (confirm != true) return;
        }
        // Fully scored — save.
        ref.read(calculatorProvider.notifier).deselectGame();
        popIfMounted();
        return;
      }
      if (state.isEditingExistingRound) {
        if (state.canRollbackWithPartial) {
          if (!context.mounted) return;
          final confirm = await showConfirmDialog(
            context,
            title: 'Score niet compleet',
            contentText: _incompleteScoreSavePrompt,
            confirmLabel: 'Opslaan',
          );
          if (confirm != true) return;
          ref.read(calculatorProvider.notifier).rollbackLastRound();
          popIfMounted();
          return;
        }
        showIncompleteFormSnackBar(
          ScaffoldMessenger.of(context),
          message: 'Vul de score volledig in om op te slaan',
        );
        return;
      }
      if (!state.hasActiveChanges) {
        // Nothing entered — treat as discard, no confirmation needed.
        ref.read(calculatorProvider.notifier).discardGame();
        popIfMounted();
        return;
      }
      // hasActiveChanges is true — always confirm before saving as pending.
      if (!context.mounted) return;
      final confirm = await showConfirmDialog(
        context,
        title: 'Score niet compleet',
        contentText: _incompleteScoreSavePrompt,
        confirmLabel: 'Opslaan',
      );
      if (confirm != true) return;
      ref.read(calculatorProvider.notifier).deselectGame();
      popIfMounted();
    }

    return PopScope(
      // Always intercept back so the discard-confirmation can run.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(saveOrConfirmBack());
      },
      child: AppScaffold(
        appBar: AppBar(
          title: TitleWithRules(
            title: Text(game.name, overflow: TextOverflow.ellipsis),
            singleGameId: game.id,
            tooltip: 'Spelregels ${game.name}',
            flexibleTitle: true,
            starterVariantOverride: ref.read(
              calculatorProvider.select((s) => s.starterVariant),
            ),
            heartsVariantOverride: ref.read(
              calculatorProvider.select((s) => s.heartsVariant),
            ),
          ),
          leading: Tooltip(
            message: 'Terug',
            child: BackButton(onPressed: saveOrConfirmBack),
          ),
          actions: [
            TextButton(
              onPressed: confirmAndCancelInput,
              child: const Text('Verwerpen'),
            ),
            FilledButton(
              onPressed: saveOrConfirmDone,
              child: const Text('Opslaan'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _RoundInputBody(game: game),
      ),
    );
  }
}

class _RoundInputBody extends ConsumerWidget {
  const _RoundInputBody({required this.game});

  final MiniGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPositive = game.category == GameCategory.positive;
    final textColor = scoreColor(isPositive ? 1 : -1, context);
    final heartsVariant = ref.watch(
      calculatorProvider.select((s) => s.heartsVariant),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RoundInputHeader(
          game: game,
          isPositive: isPositive,
          textColor: textColor,
        ),
        const SizedBox(height: 20),
        _ChooserSelectorCard(game: game),
        ..._gameRulesWarnings(game, heartsVariant),
        const SizedBox(height: 12),
        const _DoublesCard(),
        const SizedBox(height: 12),
        _InputFormCard(game: game),
        const SizedBox(height: 32),
        _ScoreResultSection(game: game),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ChooserSelectorCard extends ConsumerWidget {
  const _ChooserSelectorCard({required this.game});

  final MiniGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (displayedPlayers, chooserId, dealerId) = ref.watch(
      calculatorProvider.select(
        (s) => (s.displayedPlayers, s.chooserId, s.dealerId),
      ),
    );
    return _ChooserSelector(
      playerNames: [for (final p in displayedPlayers) p.name],
      chooserIndex: seatIndexOf(displayedPlayers, chooserId),
      defaultChooserIndex:
          (seatIndexOf(displayedPlayers, dealerId) + 1) % playerCount,
      onChanged: (dispI) => ref
          .read(calculatorProvider.notifier)
          .setChooser(
            ref
                .read(calculatorProvider)
                .players
                .indexWhere((p) => p.id == displayedPlayers[dispI].id),
          ),
    );
  }
}

class _DoublesCard extends ConsumerWidget {
  const _DoublesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (players, chooserIndex, doubles) = ref.watch(
      calculatorProvider.select((s) => (s.players, s.chooserIndex, s.doubles)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Dubbels',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 10),
            DoublesPicker(
              players: players,
              chooserIndex: chooserIndex,
              doubles: doubles,
              onChanged: ref.read(calculatorProvider.notifier).updateDoubles,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputFormCard extends ConsumerWidget {
  const _InputFormCard({required this.game});

  final MiniGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (displayedPlayers, input) = ref.watch(
      calculatorProvider.select((s) => (s.displayedPlayers, s.input)),
    );
    if (input == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Resultaat',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 10),
            GameInputForm(
              game: game,
              players: displayedPlayers,
              input: input,
              onInputChanged: ref.read(calculatorProvider.notifier).updateInput,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreResultSection extends ConsumerWidget {
  const _ScoreResultSection({required this.game});

  final MiniGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (result, partialResult, doubles, dispChooser, dispPlayers) = ref
        .watch(
          calculatorProvider.select(
            (s) => (
              s.result,
              s.partialResult,
              s.doubles,
              s.displayedChooserIndex,
              s.displayedPlayers,
            ),
          ),
        );
    return result != null
        ? ScoreResultView(
            result: result,
            game: game,
            players: dispPlayers,
            doubles: doubles,
            chooserIndex: dispChooser,
          )
        : ScoreResultView(
            result: partialResult ?? const ScoreResult(scores: {}),
            game: game,
            players: dispPlayers,
            doubles: doubles,
            chooserIndex: dispChooser,
            isPartial: true,
          );
  }
}

/// Game-name + chooser/dealer header for [_RoundInputBody].
///
/// Watches only the player names + chooser/dealer indices so it doesn't
/// rebuild when the user types into the input form.
class _RoundInputHeader extends ConsumerWidget {
  const _RoundInputHeader({
    required this.game,
    required this.isPositive,
    required this.textColor,
  });

  final MiniGame game;
  final bool isPositive;
  final Color textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (playerNames, chooserIndex, dealerIndex, starterIndex) = ref.watch(
      calculatorProvider.select(
        (s) => (s.playerNames, s.chooserIndex, s.dealerIndex, s.starterIndex),
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
              Text(
                isPositive
                    ? 'Positief  ·  +${game.totalPoints} punten totaal'
                    : 'Negatief  ·  ${game.totalPoints} punten totaal',
                style: tt.bodyMedium?.copyWith(color: textColor),
              ),
              const SizedBox(height: 2),
              Text(
                'Kiezer: ${playerNames[chooserIndex]}  ·  '
                'Deler: ${playerNames[dealerIndex]}  ·  '
                'Uitkomst: ${playerNames[starterIndex]}',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Per-game amber warnings shown between the chooser selector and the doubles
/// card.  Surfaces every [Note] block from the rules data so any condition or
/// special rule is visible at the moment the player needs it.
List<Widget> _gameRulesWarnings(MiniGame game, HeartsVariant heartsVariant) {
  final section = gameSectionFor(game.id);
  if (section == null) return const [];
  final warningBlocks = section.blocks
      .where(
        (b) =>
            b is Note ||
            (b is VariantBlock && b.variantKind == VariantKind.hearts),
      )
      .toList();
  if (warningBlocks.isEmpty) return const [];
  return [
    const SizedBox(height: 12),
    for (int i = 0; i < warningBlocks.length; i++) ...[
      if (i > 0) const SizedBox(height: 8),
      switch (warningBlocks[i]) {
        final Note b => AmberWarningBox(label: b.label, text: b.text),
        final VariantBlock b => AmberWarningBox(
          label: b.label,
          text: b.textFor(heartsVariant),
        ),
        // unreachable — warningBlocks is pre-filtered to Note|VariantBlock
        _ => const SizedBox.shrink(),
      },
    ],
  ];
}

class _ChooserSelector extends StatelessWidget {
  const _ChooserSelector({
    required this.playerNames,
    required this.chooserIndex,
    required this.defaultChooserIndex,
    required this.onChanged,
  });

  final List<String> playerNames;
  final int chooserIndex;
  final int defaultChooserIndex;

  /// Called with the newly chosen index once the change has been
  /// confirmed (after any "are you sure?" dialog the widget shows).
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
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
            DropdownMenu<int>(
              key: ValueKey(chooserIndex),
              initialSelection: chooserIndex,
              enableSearch: false,
              requestFocusOnTap: false,
              expandedInsets: EdgeInsets.zero,
              menuStyle: const MenuStyle(visualDensity: VisualDensity.compact),
              inputDecorationTheme: const InputDecorationTheme(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              dropdownMenuEntries: [
                for (int i = 0; i < playerCount; i++)
                  DropdownMenuEntry<int>(value: i, label: playerNames[i]),
              ],
              onSelected: (selected) async {
                if (selected == null || selected == chooserIndex) return;
                if (selected == defaultChooserIndex) {
                  onChanged(selected);
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
                if (confirm == true) onChanged(selected);
              },
            ),
          ],
        ),
      ),
    );
  }
}
