import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_constraints.dart';
import '../models/hearts_variant.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/starter_variant.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/amber_warning_box.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/disabled_tap_detector.dart';
import '../widgets/form_section_card.dart';
import '../widgets/game_name_field.dart';
import '../widgets/game_rules_card.dart';
import '../widgets/incomplete_form_snackbar.dart';
import '../widgets/player_list_field.dart';

/// Full-screen dialog for editing an in-progress game: the player names and
/// their order, the dealer of the first round, and the game-rule variants.
/// Pushed with `fullscreenDialog: true` so the framework supplies the ✕
/// leading icon and (on platforms that distinguish them) the modal slide-up
/// transition.
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
      'gestart zijn worden de kiezer, dubbels en scores niet van aangepast.';

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  // Snapshot of the original controller order, used to detect player reorders
  // by identity (text edits do not affect this).
  late final List<TextEditingController> _originalControllerOrder;
  // Snapshot of original trimmed text values for text-change detection.
  // Needed because _originalControllerOrder holds the same mutable controller
  // objects as _controllers, so comparing .text would always see the current value.
  late final List<String> _originalTexts;
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
    _controllers = [
      for (final name in state.playerNames) TextEditingController(text: name),
    ];
    _originalControllerOrder = List.unmodifiable(_controllers);
    _originalTexts = [for (final c in _controllers) c.text.trim()];
    _focusNodes = List.generate(playerCount, (_) => FocusNode());
    _nameController = TextEditingController(text: state.gameName ?? '');
    _originalName = state.gameName ?? '';
    _formChanges = Listenable.merge([..._controllers, _nameController]);
  }

  bool get _orderChanged => !listEquals(_controllers, _originalControllerOrder);

  /// True if the dealer slot now points at a different *person* than it
  /// did when entering this screen. Reordering players in a way that keeps
  /// the same controller (i.e. the same person) at the dealer position is
  /// not considered a dealer change — even if the numeric [_firstDealerIndex]
  /// shifted as a result of the reorder.
  bool get _dealerPlayerChanged =>
      _controllers[_firstDealerIndex] !=
      _originalControllerOrder[_originalFirstDealerIndex];

  /// Derived on demand from the current controller texts and dealer index.
  /// Read inside the outer [ListenableBuilder] so it always reflects the
  /// live form state — no cached bit to keep in sync.
  bool get _hasChanges =>
      _controllers.indexed.any(
        (e) => e.$2.text.trim() != _originalTexts[e.$1],
      ) ||
      _firstDealerIndex != _originalFirstDealerIndex ||
      _starterVariant != _originalStarterVariant ||
      _heartsVariant != _originalHeartsVariant ||
      _nameController.text.trim() != _originalName;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
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
    // `onReorderItem` already pre-adjusts newIndex for the removed item — no
    // manual `if (newIndex > oldIndex) newIndex -= 1` decrement needed.
    var target = newIndex;
    if (target < 0) target = 0;
    if (target >= playerCount) target = playerCount - 1;
    if (target == oldIndex) return;

    setState(() {
      final c = _controllers.removeAt(oldIndex);
      _controllers.insert(target, c);
      final f = _focusNodes.removeAt(oldIndex);
      _focusNodes.insert(target, f);
      // Keep _firstDealerIndex pointing at the same person.
      _firstDealerIndex = adjustIndexAfterReorder(
        oldIndex,
        target,
        _firstDealerIndex,
      );
    });
  }

  Future<void> _confirmAndCancel() async {
    if (_hasChanges) {
      final confirmed = await showConfirmDialog(
        context,
        title: kDiscardChangesTitle,
        contentText: kDiscardChangesMessage,
        confirmLabel: kDiscardLabel,
        destructive: true,
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  void _showSaveValidationSnackbar() {
    final trimmed = _controllers.map((c) => c.text.trim()).toList();
    if (!allPlayerNamesFilled(trimmed)) {
      showIncompleteFormSnackBar(
        ScaffoldMessenger.of(context),
        message: 'Vul alle spelersnamen in.',
      );
      return;
    }
    showIncompleteFormSnackBar(
      ScaffoldMessenger.of(context),
      message: 'Spelersnamen moeten uniek zijn.',
    );
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
    // Build the new player list in the post-reorder seat order.
    // Map each controller back to the original Player object by identity so
    // UUIDs stay bound to the correct person after a drag-reorder.
    final origPlayers = ref.read(activeSessionProvider).players;
    final newPlayers = <Player>[
      for (int i = 0; i < playerCount; i++)
        () {
          final origIdx = _originalControllerOrder.indexOf(_controllers[i]);
          return origPlayers[origIdx].copyWith(
            name: _controllers[i].text.trim(),
          );
        }(),
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
    final suggestions = ref
        .watch(gameHistoryProvider.notifier)
        .playerNameSuggestions;
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
                  final canSave =
                      allPlayerNamesFilled(trimmed) &&
                      !hasDuplicatePlayerNames(trimmed);
                  return DisabledTapDetector(
                    enabled: !canSave,
                    onTap: _showSaveValidationSnackbar,
                    child: FilledButton(
                      onPressed: canSave ? _save : null,
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
