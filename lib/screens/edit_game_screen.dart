import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_constraints.dart';
import '../models/hearts_variant.dart';
import '../models/player.dart';
import '../models/starter_variant.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/amber_warning_box.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/disabled_tappable_button.dart';
import '../widgets/form_section_card.dart';
import '../widgets/game_name_field.dart';
import '../widgets/game_rules_card.dart';
import '../widgets/player_list_field.dart';
import '../widgets/timed_snackbar.dart';

/// One editable player row in [EditGameScreen]. Bundles the original [Player]
/// (whose UUID and name stay fixed) with its text controller, focus node, and
/// entry seat index so that reordering the list moves the whole record — the
/// UUID stays bound to the right person without an identity-rebind step.
typedef _PlayerField = ({
  Player player,
  TextEditingController controller,
  FocusNode focusNode,
  int originalIndex,
});

/// Full-screen dialog for editing an in-progress game: the player names and
/// their order, the dealer of the first round, and the game-rule variants.
/// Pushed with `fullscreenDialog: true` — deliberately a dialog, not a screen,
/// so per Material 3 it gets a close (✕) affordance and the modal slide-up
/// transition rather than a back arrow. The leading ✕ is a custom `IconButton`
/// (not the framework-supplied one): the framework's offers no hook to run the
/// unsaved-changes discard confirm, so this one wires `onPressed` to it.
class EditGameScreen extends ConsumerStatefulWidget {
  const EditGameScreen({super.key});

  @override
  ConsumerState<EditGameScreen> createState() => _EditGameScreenState();
}

class _EditGameScreenState extends ConsumerState<EditGameScreen> {
  // Short labels shown both in-line under their respective fields and
  // listed in the confirmation dialog when saving while a game is in progress.
  static const _playerOrderShortWarning =
      'De volgorde van de spelers wordt aangepast.';
  static const _dealerShortWarning =
      'De deler van de eerste ronde wordt aangepast.';
  static const _inProgressEffectExplanation =
      'Dit heeft alleen effect bij invoer van een nieuwe ronde. Van reeds '
      'ingevoerde rondes (ook die van de eerste ronde) en rondes die al '
      'gestart zijn worden de kiezer, dubbels en scores niet aangepast.';

  // One row per seat: the original [Player] (stable UUID + original name), its
  // editable text controller and focus node, and where it sat on entry. Because
  // a reorder moves the *whole* record, the UUID↔seat binding is preserved by
  // construction — no separate "original order" snapshot or identity rebind.
  late final List<_PlayerField> _fields;
  late int _firstDealerIndex;
  late final bool _gameInProgress;
  late final int _originalFirstDealerIndex;
  late StarterVariant _starterVariant;
  late final StarterVariant _originalStarterVariant;
  late HeartsVariant _heartsVariant;
  late final HeartsVariant _originalHeartsVariant;
  late final TextEditingController _nameController;
  late final String _originalName;
  // Listenable that fires on any controller text change. Combined with
  // `setState`-driven dealer/reorder updates, this is what the outer
  // [ListenableBuilder] subscribes to so [PopScope.canPop] stays in sync
  // with [_hasChanges] without us caching a derived bool.
  late final Listenable _formChanges;

  @override
  void initState() {
    super.initState();
    final state = ref.read(activeSessionProvider);
    _firstDealerIndex = state.firstDealerIndex;
    _originalFirstDealerIndex = state.firstDealerIndex;
    _gameInProgress = state.history.isNotEmpty || state.hasPendingGame;
    _starterVariant = state.ruleVariants.starterVariant;
    _originalStarterVariant = state.ruleVariants.starterVariant;
    _heartsVariant = state.ruleVariants.heartsVariant;
    _originalHeartsVariant = state.ruleVariants.heartsVariant;
    _fields = [
      for (final (i, player) in state.players.indexed)
        (
          player: player,
          controller: TextEditingController(text: player.name),
          focusNode: FocusNode(),
          originalIndex: i,
        ),
    ];
    _nameController = TextEditingController(text: state.gameName ?? '');
    _originalName = state.gameName ?? '';
    _formChanges = Listenable.merge([
      for (final f in _fields) f.controller,
      _nameController,
    ]);
  }

  /// Live views over [_fields] in the current seat order, for the shared
  /// widgets/helpers that take parallel controller/focus-node lists.
  List<TextEditingController> get _controllers => [
    for (final f in _fields) f.controller,
  ];
  List<FocusNode> get _focusNodes => [for (final f in _fields) f.focusNode];

  /// True once any field no longer sits at its entry seat — i.e. the player
  /// order changed. The "where did I start" marker travels with each field.
  bool get _orderChanged =>
      _fields.indexed.any((e) => e.$2.originalIndex != e.$1);

  /// True if the dealer slot now points at a different *person* than it
  /// did when entering this screen. Reordering players in a way that keeps
  /// the same person at the dealer position is not considered a dealer change
  /// — even if the numeric [_firstDealerIndex] shifted as a result.
  bool get _dealerPlayerChanged =>
      _fields[_firstDealerIndex].originalIndex != _originalFirstDealerIndex;

  /// Derived on demand from the current field texts and dealer index. Read
  /// inside the outer [ListenableBuilder] so it always reflects the live form
  /// state — no cached bit to keep in sync.
  bool get _hasChanges =>
      _fields.any((f) => f.controller.text.trim() != f.player.name) ||
      _firstDealerIndex != _originalFirstDealerIndex ||
      _starterVariant != _originalStarterVariant ||
      _heartsVariant != _originalHeartsVariant ||
      _nameController.text.trim() != _originalName;

  @override
  void dispose() {
    for (final f in _fields) {
      f.controller.dispose();
      f.focusNode.dispose();
    }
    _nameController.dispose();
    super.dispose();
  }

  void _handleFieldSubmitted(int index) => handlePlayerFieldSubmitted(
    index: index,
    controllers: _controllers,
    focusNodes: _focusNodes,
  );

  void _onReorder(int oldIndex, int newIndex) {
    // Moves the field and keeps _firstDealerIndex pointing at the same person.
    // The dealer index is non-null here, so the helper never returns null.
    setState(() {
      _firstDealerIndex = reorderPlayerFields(
        _fields,
        oldIndex,
        newIndex,
        _firstDealerIndex,
      )!;
    });
  }

  Future<void> _confirmAndCancel() async {
    final proceed = await confirmDiscard(
      context,
      dirty: _hasChanges,
      title: kDiscardChangesTitle,
      message: kDiscardChangesMessage,
    );
    if (!proceed) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _showSaveValidationSnackbar() {
    final reason = playerNamesInvalidReason(
      _controllers.map((c) => c.text.trim()).toList(),
    );
    if (reason == null) return;
    showTimedSnackBar(ScaffoldMessenger.of(context), content: Text(reason));
  }

  Future<void> _save() async {
    final dealerChanged = _dealerPlayerChanged;
    final orderChanged = _orderChanged;
    if (_gameInProgress && (dealerChanged || orderChanged)) {
      final confirm = await showConfirmDialog(
        context,
        title: 'Lopend spel wijzigen',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (orderChanged)
              const AmberWarningBox(text: _playerOrderShortWarning),
            if (orderChanged && dealerChanged) const SizedBox(height: 8),
            if (dealerChanged) const AmberWarningBox(text: _dealerShortWarning),
            const SizedBox(height: 12),
            Text(
              _inProgressEffectExplanation,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        confirmLabel: 'Wijzigen',
      );
      if (confirm != true) return;
      if (!mounted) return;
    }
    // Build the new player list in the post-reorder seat order. Each field
    // carries its original Player, so the UUID stays bound to the right person
    // by construction — we just apply the (possibly edited) name.
    final newPlayers = <Player>[
      for (final f in _fields)
        f.player.copyWith(name: f.controller.text.trim()),
    ];
    final notifier = ref.read(calculatorProvider.notifier);
    notifier.setPlayersAndDealer(newPlayers, _firstDealerIndex);
    notifier.setStarterVariant(_starterVariant);
    notifier.setHeartsVariant(_heartsVariant);
    notifier.setGameName(normalizeGameName(_nameController.text));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Holds a subscription so autoDispose doesn't cascade while initState/_save use ref.read.
    ref.watch(calculatorProvider);
    final suggestions = ref.watch(playerNameSuggestionsProvider);
    final orderChanged = _orderChanged;

    return ListenableBuilder(
      listenable: _formChanges,
      builder: (context, child) => PopScope(
        canPop: !_hasChanges,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_confirmAndCancel());
        },
        child: child!,
      ),
      child: AppScaffold(
        appBar: AppBar(
          title: const Text('Spel bewerken'),
          leading: IconButton(
            icon: const Icon(Symbols.close),
            tooltip: kDiscardLabel,
            onPressed: _confirmAndCancel,
          ),
        ),
        bottomBar: BottomAppBar(
          child: Row(
            children: [
              TextButton(
                onPressed: _confirmAndCancel,
                child: const Text(kDiscardLabel),
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: _formChanges,
                builder: (context, _) {
                  final trimmed = _controllers
                      .map((c) => c.text.trim())
                      .toList();
                  final canSave = playerNamesInvalidReason(trimmed) == null;
                  return DisabledTappableButton(
                    onPressed: canSave ? _save : null,
                    onDisabledTap: _showSaveValidationSnackbar,
                    builder: (onPressed) => FilledButton(
                      onPressed: onPressed,
                      child: const Text(kSaveLabel),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSectionCard(
              title: kPlayersSectionTitle,
              subtitle: kPlayersSectionSubtitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListenableBuilder(
                    listenable: _formChanges,
                    builder: (context, _) => PlayerListField(
                      controllers: _controllers,
                      focusNodes: _focusNodes,
                      suggestions: suggestions,
                      onReorderItem: _onReorder,
                      onSubmitted: _handleFieldSubmitted,
                    ),
                  ),
                  if (_gameInProgress && orderChanged) ...[
                    const SizedBox(height: 12),
                    const AmberWarningBox(text: _playerOrderShortWarning),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            FormSectionCard(
              title: kDealerSectionTitle,
              subtitle: kDealerSectionSubtitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListenableBuilder(
                    listenable: _formChanges,
                    builder: (context, _) => DealerDropdownField(
                      controllers: _controllers,
                      value: _firstDealerIndex,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _firstDealerIndex = v);
                      },
                    ),
                  ),
                  if (_gameInProgress && _dealerPlayerChanged) ...[
                    const SizedBox(height: 12),
                    const AmberWarningBox(text: _dealerShortWarning),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            GameNameField(controller: _nameController),
            const SizedBox(height: 12),
            GameRulesCard(
              starterVariant: _starterVariant,
              heartsVariant: _heartsVariant,
              onStarterChanged: (v) => setState(() => _starterVariant = v),
              onHeartsChanged: (v) => setState(() => _heartsVariant = v),
            ),
          ],
        ),
      ),
    );
  }
}
