import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_constraints.dart';
import '../models/hearts_variant.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/rule_variants.dart';
import '../models/starter_variant.dart';
import '../state/calculator_provider.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/form_section_card.dart';
import '../widgets/game_name_field.dart';
import '../widgets/game_rules_card.dart';
import '../widgets/incomplete_form_snackbar.dart';
import '../widgets/player_list_field.dart';
import 'game_screen.dart';

/// Full-screen dialog for entering player names and picking the dealer.
///
/// Holds purely local working state — the [calculatorProvider] is only
/// mutated when the user confirms "Start spel". Closing via the ✕ button
/// (or back gesture) shows a discard-confirmation dialog whenever any field
/// has been filled in; tapping ✕ on a blank form pops immediately.
class NewGameScreen extends ConsumerStatefulWidget {
  const NewGameScreen({super.key});

  @override
  ConsumerState<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final TextEditingController _nameController;

  /// Dealer slot index, or null if the user wants a random dealer.
  int? _dealerIndex;

  late StarterVariant _starterVariant;
  late HeartsVariant _heartsVariant;
  // Listenable that fires on any controller text change — drives the
  // [ListenableBuilder] that keeps [PopScope.canPop] in sync with [_hasInput].
  late final Listenable _formChanges;

  @override
  void initState() {
    super.initState();
    _starterVariant = ref.read(defaultStarterVariantProvider);
    _heartsVariant = ref.read(defaultHeartsVariantProvider);
    // Always start with empty fields. Names from a previous (finished or
    // resumed) session live in the calculator provider, but surfacing them
    // here is confusing — the user reached this screen by pressing
    // "Nieuw spel", which should mean a clean slate.
    _controllers = List.generate(playerCount, (_) {
      final c = TextEditingController();
      // Rebuild on every keystroke so the duplicate warning, dropdown
      // labels, and Start-button enabled-state stay in sync.
      c.addListener(_onAnyChange);
      return c;
    });
    _focusNodes = List.generate(playerCount, (_) => FocusNode());
    _nameController = TextEditingController();
    _formChanges = Listenable.merge([..._controllers, _nameController]);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c
        ..removeListener(_onAnyChange)
        ..dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    _nameController.dispose();
    super.dispose();
  }

  void _onAnyChange() {
    if (mounted) setState(() {});
  }

  /// True when any field has been touched — used to decide whether closing
  /// should ask for confirmation.
  bool get _hasInput =>
      _controllers.any((c) => c.text.trim().isNotEmpty) ||
      _nameController.text.trim().isNotEmpty ||
      _dealerIndex != null;

  Future<void> _confirmAndCancel() async {
    if (_hasInput) {
      final confirmed = await showConfirmDialog(
        context,
        title: kDiscardInputTitle,
        contentText: kDiscardInputMessage,
        confirmLabel: kDiscardLabel,
        destructive: true,
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  /// Called when the user presses Enter on the slot at [index].
  /// If the next slot exists and is still empty, focus it so the user can
  /// keep typing.  Otherwise unfocus the current field so the cursor
  /// disappears.
  void _handleFieldSubmitted(int index) => handlePlayerFieldSubmitted(
    index: index,
    controllers: _controllers,
    focusNodes: _focusNodes,
  );

  void _handleReorder(int oldIndex, int newIndex) {
    // `onReorderItem` already pre-adjusts newIndex for the removed item — no
    // manual `if (newIndex > oldIndex) newIndex -= 1` decrement needed.
    final target = newIndex;
    if (oldIndex == target) return;
    setState(() {
      final movedC = _controllers.removeAt(oldIndex);
      _controllers.insert(target, movedC);
      final movedN = _focusNodes.removeAt(oldIndex);
      _focusNodes.insert(target, movedN);
      if (_dealerIndex != null) {
        _dealerIndex = adjustIndexAfterReorder(oldIndex, target, _dealerIndex!);
      }
    });
  }

  void _showStartValidationSnackbar() {
    final trimmedNames = [for (final c in _controllers) c.text.trim()];
    if (!allPlayerNamesFilled(trimmedNames)) {
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

  Future<void> _handleStart() async {
    final trimmedNames = [for (final c in _controllers) c.text.trim()];
    final players = [for (final n in trimmedNames) Player(name: n)];

    final dealerWasRandom = _dealerIndex == null;
    final dealerIndex = _dealerIndex ?? Random().nextInt(playerCount);

    if (dealerWasRandom) {
      await showDealerAnnouncementDialog(
        context,
        dealerName: players[dealerIndex].name,
      );
      if (!mounted) return;
    }

    // Hold a subscription to bridge the gap between ref.read() closing its
    // temporary sub and GameScreen subscribing. The await saveGame() below
    // yields to the microtask queue, where the autoDispose timer would
    // otherwise fire and dispose calculatorProvider before GameScreen builds.
    final container = ProviderScope.containerOf(context, listen: false);
    final sub = container.listen<CalculatorState>(
      calculatorProvider,
      (_, _) {},
    );
    final notifier = ref.read(calculatorProvider.notifier);
    notifier.startNewGame(
      players: players,
      dealerIndex: dealerIndex,
      ruleVariants: RuleVariants(
        starterVariant: _starterVariant,
        heartsVariant: _heartsVariant,
      ),
      gameName: normalizeGameName(_nameController.text),
    );
    final session = notifier.buildSession();
    if (session != null) {
      await ref.read(gameHistoryProvider.notifier).saveGame(session);
    }
    if (!mounted) {
      sub.close();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => sub.close());
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch history so suggestions update if it finishes loading after this
    // widget is first built.
    final suggestions = ref
        .watch(gameHistoryProvider.notifier)
        .playerNameSuggestions;
    final trimmedNames = [for (final c in _controllers) c.text.trim()];
    final canStart =
        allPlayerNamesFilled(trimmedNames) &&
        !hasDuplicatePlayerNames(trimmedNames);

    return ListenableBuilder(
      listenable: _formChanges,
      builder: (context, child) => PopScope(
        canPop: !_hasInput,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_confirmAndCancel());
        },
        child: child!,
      ),
      child: AppScaffold(
        appBar: AppBar(
          title: const Text('Nieuw spel'),
          leading: IconButton(
            icon: const Icon(Symbols.close),
            tooltip: kDiscardLabel,
            onPressed: _confirmAndCancel,
          ),
        ),
        bottomBar: FullWidthBottomBarButton(
          icon: const Icon(Symbols.play_arrow),
          label: const Text('Start spel'),
          onPressed: canStart ? _handleStart : null,
          onDisabledTap: _showStartValidationSnackbar,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSectionCard(
              title: kPlayersSectionTitle,
              subtitle: kPlayersSectionSubtitle,
              child: PlayerListField(
                controllers: _controllers,
                focusNodes: _focusNodes,
                suggestions: suggestions,
                onReorderItem: _handleReorder,
                onSubmitted: _handleFieldSubmitted,
              ),
            ),

            const SizedBox(height: 12),

            FormSectionCard(
              title: kDealerSectionTitle,
              subtitle: kDealerSectionSubtitle,
              child: DealerDropdownField(
                controllers: _controllers,
                value: _dealerIndex,
                allowRandomDealer: true,
                onChanged: (v) => setState(() => _dealerIndex = v),
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
