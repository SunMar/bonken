import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/hearts_variant.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/starter_variant.dart';
import '../state/calculator_provider.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/form_section_card.dart';
import '../widgets/game_rules_expansion_card.dart';
import '../widgets/player_list_field.dart';
import '../widgets/primary_action_button.dart';
import 'game_screen.dart';

/// Second screen: enter player names and pick the dealer for the first game.
///
/// Holds purely local working state — the [calculatorProvider] is only
/// mutated when the user confirms "Start spel". Backing out of this screen
/// therefore requires no cleanup.
class NewGameScreen extends ConsumerStatefulWidget {
  const NewGameScreen({super.key});

  @override
  ConsumerState<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  /// Dealer slot index, or null if the user wants a random dealer.
  int? _dealerIndex;

  late StarterVariant _starterVariant;
  late HeartsVariant _heartsVariant;

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
    super.dispose();
  }

  void _onAnyChange() {
    if (mounted) setState(() {});
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

  Future<void> _handleStart() async {
    final players = [for (final c in _controllers) Player(name: c.text.trim())];

    final dealerWasRandom = _dealerIndex == null;
    final dealerIndex = _dealerIndex ?? Random().nextInt(playerCount);

    if (dealerWasRandom) {
      await showDealerAnnouncementDialog(
        context,
        dealerName: players[dealerIndex].name,
      );
      if (!mounted) return;
    }

    final notifier = ref.read(calculatorProvider.notifier);
    notifier.startNewGame(
      players: players,
      dealerIndex: dealerIndex,
      starterVariant: _starterVariant,
      heartsVariant: _heartsVariant,
    );
    final session = notifier.buildSession();
    if (session != null) {
      await ref.read(gameHistoryProvider.notifier).saveGame(session);
    }
    if (!mounted) return;
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
    final lowerNames = trimmedNames.map((n) => n.toLowerCase()).toList();
    final canStart =
        trimmedNames.every((n) => n.isNotEmpty) &&
        lowerNames.toSet().length == playerCount;

    return AppScaffold(
      appBar: AppBar(title: const Text('Nieuw spel')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scrollable options — players, dealer, variant
          Expanded(
            child: ListView(
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
                    hintText: 'Willekeurige deler',
                    allowRandomDealer: true,
                    onChanged: (v) => setState(() => _dealerIndex = v),
                  ),
                ),

                const SizedBox(height: 12),

                GameRulesExpansionCard(
                  starterVariant: _starterVariant,
                  heartsVariant: _heartsVariant,
                  onStarterChanged: (v) => setState(() => _starterVariant = v),
                  onHeartsChanged: (v) => setState(() => _heartsVariant = v),
                ),
              ],
            ),
          ),

          // Fixed Start button — always visible without scrolling
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: PrimaryActionButton(
              icon: const Icon(Symbols.play_arrow),
              label: const Text('Start spel'),
              onPressed: canStart ? _handleStart : null,
            ),
          ),
        ],
      ),
    );
  }
}
