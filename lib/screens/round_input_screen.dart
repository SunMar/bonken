import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/game_rules.dart';
import '../models/game_mechanics.dart';
import '../models/hearts_variant.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/score_result.dart';
import '../state/calculator_provider.dart';
import '../state/rules_edit_mode_provider.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';
import '../widgets/amber_warning_box.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/disabled_tappable_button.dart';
import '../widgets/doubles_picker.dart';
import '../widgets/game_avatar.dart';
import '../widgets/game_input/game_input_form.dart';
import '../widgets/round_meta_line.dart';
import '../widgets/score_result_view.dart';
import '../widgets/timed_snackbar.dart';

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
  late final MiniGame _game = ref.read(activeSessionProvider).selectedGame!;

  void _popIfMounted() {
    if (context.mounted) Navigator.of(context).pop();
  }

  /// Whether this screen is re-editing a saved round (vs entering a pending
  /// one). Fixed for the screen's lifetime; read on demand by the handlers.
  bool _isEditing() => ref.read(activeSessionProvider).isEditingExistingRound;

  void _cancelInputPhase() {
    if (_isEditing()) {
      ref.read(calculatorProvider.notifier).cancelEditRound();
    } else {
      ref.read(calculatorProvider.notifier).discardGame();
    }
    _popIfMounted();
  }

  Future<void> _confirmAndCancelInput() async {
    final isEditing = _isEditing();
    final hasChanges = ref.read(
      activeSessionProvider.select((a) => a.hasActiveChanges),
    );
    final proceed = await confirmDiscard(
      context,
      dirty: hasChanges,
      title: isEditing ? kDiscardChangesTitle : 'Ronde verwerpen',
      message: isEditing
          ? kDiscardChangesMessage
          : 'De dubbels en scores van de huidige ronde worden verworpen.',
    );
    if (!proceed) return;
    _cancelInputPhase();
  }

  // Only called for pending rounds (editing uses _confirmAndCancelInput).
  Future<void> _exitPendingRound() async {
    final hasChanges = ref.read(
      activeSessionProvider.select((a) => a.hasActiveChanges),
    );
    if (hasChanges) {
      ref.read(calculatorProvider.notifier).exitPendingSlot();
    } else {
      ref.read(calculatorProvider.notifier).discardGame();
    }
    _popIfMounted();
  }

  // Only called when the input is complete (the save button enables only then).
  Future<void> _confirmAndSave() async {
    final s = ref.read(activeSessionProvider);
    if (s.hasActiveChanges) {
      if (!context.mounted) return;
      final confirm = await showConfirmDialog(
        context,
        title: 'Score',
        content: SingleChildScrollView(
          child: ScoreResultView(
            result: s.result!,
            game: s.selectedGame!,
            players: s.displayedPlayers,
            doubles: s.doubles,
            chooserIndex: s.displayedChooserIndex,
            showHeader: false,
          ),
        ),
        confirmLabel: kSaveLabel,
      );
      if (confirm != true) return;
    }
    ref.read(calculatorProvider.notifier).deselectGame();
    _popIfMounted();
  }

  void _showSaveIncompleteSnackbar() {
    showTimedSnackBar(
      ScaffoldMessenger.of(context),
      content: const Text('Vul de score volledig in om op te slaan.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final isEditing = ref.watch(
      activeSessionProvider.select((a) => a.isEditingExistingRound),
    );
    final isComplete = ref.watch(
      activeSessionProvider.select((a) => a.inputState == InputState.complete),
    );

    return PopScope(
      // Always intercept back so the appropriate discard handler can run.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(isEditing ? _confirmAndCancelInput() : _exitPendingRound());
        }
      },
      child: AppScaffold(
        appBar: AppBar(
          title: TitleWithRules(
            title: Text(game.name, overflow: TextOverflow.ellipsis),
            singleGameId: game.id,
            tooltip: 'Spelregels ${game.name}',
            flexibleTitle: true,
            starterVariantOverride: ref.read(
              activeSessionProvider.select(
                (a) => a.ruleVariants.starterVariant,
              ),
            ),
            heartsVariantOverride: ref.read(
              activeSessionProvider.select((a) => a.ruleVariants.heartsVariant),
            ),
            editMode: RulesEditMode.hidden,
          ),
          leading: isEditing
              ? IconButton(
                  icon: const Icon(Symbols.close),
                  tooltip: kDiscardLabel,
                  onPressed: _confirmAndCancelInput,
                )
              : Tooltip(
                  message: 'Terug',
                  child: BackButton(onPressed: _exitPendingRound),
                ),
        ),
        bottomBar: BottomAppBar(
          child: Row(
            children: [
              TextButton(
                onPressed: _confirmAndCancelInput,
                child: const Text(kDiscardLabel),
              ),
              const Spacer(),
              DisabledTappableButton(
                onPressed: isComplete ? _confirmAndSave : null,
                onDisabledTap: _showSaveIncompleteSnackbar,
                builder: (onPressed) => FilledButton(
                  onPressed: onPressed,
                  child: const Text(kSaveLabel),
                ),
              ),
            ],
          ),
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
      activeSessionProvider.select((a) => a.ruleVariants.heartsVariant),
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
      activeSessionProvider.select(
        (a) => (a.displayedPlayers, a.chooserId, a.dealerId),
      ),
    );
    return _ChooserSelector(
      playerNames: [for (final p in displayedPlayers) p.name],
      chooserIndex: seatIndexOf(displayedPlayers, chooserId),
      defaultChooserIndex: chooserIndexFor(
        seatIndexOf(displayedPlayers, dealerId),
      ),
      onChanged: (dispI) => ref
          .read(calculatorProvider.notifier)
          .setChooser(
            seatIndexOf(
              ref.read(activeSessionProvider).players,
              displayedPlayers[dispI].id,
            ),
          ),
    );
  }
}

class _DoublesCard extends ConsumerWidget {
  const _DoublesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (players, chooserIndex, doubles) = ref.watch(
      activeSessionProvider.select(
        (a) => (a.players, a.chooserIndex, a.doubles),
      ),
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
      activeSessionProvider.select((a) => (a.displayedPlayers, a.input)),
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
          activeSessionProvider.select(
            (a) => (
              a.result,
              a.partialResult,
              a.doubles,
              a.displayedChooserIndex,
              a.displayedPlayers,
            ),
          ),
        );
    return ScoreResultView(
      result: result ?? partialResult ?? const ScoreResult(scores: {}),
      game: game,
      players: dispPlayers,
      doubles: doubles,
      chooserIndex: dispChooser,
      isPartial: result == null,
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
      activeSessionProvider.select(
        (a) => (a.playerNames, a.chooserIndex, a.dealerIndex, a.starterIndex),
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
              RoundMetaLine(
                color: cs.onSurfaceVariant,
                segments: [
                  'Kiezer: ${playerNames[chooserIndex]}',
                  'Deler: ${playerNames[dealerIndex]}',
                  'Uitkomst: ${playerNames[starterIndex]}',
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Per-game amber warnings shown between the chooser selector and the doubles
/// card.  Surfaces the rules blocks a player needs reminding of mid-game: every
/// [Note] block, plus any in-game-relevant [VariantBlock] (currently the active
/// hearts variant), so the condition or special rule is visible at the moment
/// it applies.
List<Widget> _gameRulesWarnings(MiniGame game, HeartsVariant heartsVariant) {
  final section = gameSectionFor(game.id);
  if (section == null) return const [];
  // Map matching blocks straight to their warning boxes: a typed collection-if
  // yields only the two relevant cases, so there is no unreachable default arm.
  final boxes = <AmberWarningBox>[
    for (final b in section.blocks)
      if (b is Note)
        AmberWarningBox(label: b.label, text: b.text)
      else if (b is VariantBlock && b.variantKind == VariantKind.hearts)
        AmberWarningBox(label: b.label, text: b.textFor(heartsVariant)),
  ];
  if (boxes.isEmpty) return const [];
  return [
    const SizedBox(height: 12),
    for (int i = 0; i < boxes.length; i++) ...[
      if (i > 0) const SizedBox(height: 8),
      boxes[i],
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
            // The visible heading doubles as the dropdown's programmatic label
            // (added below), so exclude it from the semantics tree to avoid a
            // screen reader announcing "Wie koos dit spel?" twice.
            ExcludeSemantics(
              child: Text(
                'Wie koos dit spel?',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 6),
            // Labelled for assistive tech: a bare DropdownMenu exposes only its
            // current value (the chooser's name), never its purpose.
            // `selectOnly` makes the inner field a genuine read-only picker (not
            // a search box); `requestFocusOnTap: false` additionally keeps the
            // mobile keyboard hidden. No `ValueKey` is needed — DropdownMenu
            // re-seeds its displayed value from `initialSelection` on a rebuild.
            MergeSemantics(
              child: Semantics(
                label: 'Wie koos dit spel?',
                child: DropdownMenu<int>(
                  initialSelection: chooserIndex,
                  selectOnly: true,
                  requestFocusOnTap: false,
                  expandedInsets: EdgeInsets.zero,
                  menuStyle: const MenuStyle(
                    visualDensity: VisualDensity.compact,
                  ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
