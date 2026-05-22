import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/mini_game.dart';
import '../models/player.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/amber_warning_box.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/incomplete_form_snackbar.dart';
import '../widgets/player_list_field.dart';

/// Full-screen dialog for editing the player names and the dealer of the
/// first round.  Pushed with `fullscreenDialog: true` so the framework
/// supplies the ✕ leading icon and (on platforms that distinguish them)
/// the modal slide-up transition.
class EditPlayersScreen extends ConsumerStatefulWidget {
  const EditPlayersScreen({super.key});

  @override
  ConsumerState<EditPlayersScreen> createState() => _EditPlayersScreenState();
}

class _EditPlayersScreenState extends ConsumerState<EditPlayersScreen> {
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
  // Listenable that fires on any controller text change. Combined with
  // `setState`-driven dealer/reorder updates, this is what the outer
  // [ListenableBuilder] subscribes to so [PopScope.canPop] stays in sync
  // with [_hasChanges] without us caching a derived bool.
  late final Listenable _formChanges;

  @override
  void initState() {
    super.initState();
    final state = ref.read(calculatorProvider);
    _firstDealerIndex = state.firstDealerIndex;
    _originalFirstDealerIndex = state.firstDealerIndex;
    _gameInProgress = state.history.isNotEmpty || state.hasPendingGame;
    _controllers = [
      for (final name in state.playerNames) TextEditingController(text: name),
    ];
    _originalControllerOrder = List.unmodifiable(_controllers);
    _originalTexts = [for (final c in _controllers) c.text.trim()];
    _focusNodes = List.generate(playerCount, (_) => FocusNode());
    _formChanges = Listenable.merge(_controllers);
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
      _firstDealerIndex != _originalFirstDealerIndex;

  @override
  void dispose() {
    for (final c in _controllers) {
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
        title: 'Wijzigingen verwerpen',
        contentText: kDiscardChangesMessage,
        confirmLabel: 'Verwerpen',
        destructive: true,
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final trimmed = _controllers.map((c) => c.text.trim()).toList();
    if (trimmed.any((n) => n.isEmpty)) {
      showIncompleteFormSnackBar(
        ScaffoldMessenger.of(context),
        message: 'Vul alle spelersnamen in',
      );
      return;
    }
    if (trimmed.map((n) => n.toLowerCase()).toSet().length != trimmed.length) {
      showIncompleteFormSnackBar(
        ScaffoldMessenger.of(context),
        message: 'Spelersnamen moeten uniek zijn',
      );
      return;
    }
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
            if (orderChanged) AmberWarningBox(text: _playerOrderShortWarning),
            if (orderChanged && dealerChanged) const SizedBox(height: 8),
            if (dealerChanged) AmberWarningBox(text: _dealerShortWarning),
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
    final origPlayers = ref.read(calculatorProvider).players;
    final newPlayers = <Player>[
      for (int i = 0; i < playerCount; i++)
        () {
          final origIdx = _originalControllerOrder.indexOf(_controllers[i]);
          return origPlayers[origIdx].copyWith(
            name: _controllers[i].text.trim(),
          );
        }(),
    ];
    ref
        .read(calculatorProvider.notifier)
        .setPlayersAndDealer(newPlayers, _firstDealerIndex);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = ref
        .watch(gameHistoryProvider.notifier)
        .playerNameSuggestions;
    final orderChanged = _orderChanged;

    return ListenableBuilder(
      listenable: _formChanges,
      builder: (context, child) => PopScope(
        canPop: !_hasChanges,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmAndCancel();
        },
        child: child!,
      ),
      child: AppScaffold(
        appBar: AppBar(
          title: const Text('Spel bewerken'),
          leading: IconButton(
            icon: const Icon(Symbols.close),
            tooltip: 'Verwerpen',
            onPressed: _confirmAndCancel,
          ),
          actions: [
            TextButton(
              onPressed: _confirmAndCancel,
              child: const Text('Verwerpen'),
            ),
            FilledButton(onPressed: _save, child: const Text('Opslaan')),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spelers',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sleep om de volgorde te wijzigen.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: _formChanges,
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
                      AmberWarningBox(text: _playerOrderShortWarning),
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
                      AmberWarningBox(text: _dealerShortWarning),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
