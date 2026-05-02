import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/mini_game.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../utils.dart';
import '../widgets/dialogs.dart';
import '../widgets/player_list_field.dart';
import 'calculator_screen.dart';

/// Second screen: enter player names and pick the dealer for the first game.
///
/// Holds purely local working state — the [calculatorProvider] is only
/// mutated when the user confirms "Start spel". Backing out of this screen
/// therefore requires no cleanup.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  /// Dealer slot index, or null if the user wants a random dealer.
  int? _dealerIndex;

  @override
  void initState() {
    super.initState();
    // Pre-seed from any names already sitting in the provider. This is how
    // the "Nieuw spel met dezelfde spelers" button on the finished-game
    // screen carries names over: it calls setAllPlayerNames(...) before
    // pushing this screen. For a fresh "Nieuw spel" from the start screen
    // the provider holds four empty strings, so nothing is pre-filled.
    final initialNames = ref.read(calculatorProvider).playerNames;
    _controllers = List.generate(playerCount, (i) {
      final c = TextEditingController(
        text: i < initialNames.length ? initialNames[i] : '',
      );
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
    var target = newIndex;
    if (target > oldIndex) target -= 1;
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
    final names = [for (final c in _controllers) c.text.trim()];

    final dealerWasRandom = _dealerIndex == null;
    final dealerIndex = _dealerIndex ?? Random().nextInt(playerCount);

    if (dealerWasRandom) {
      final dealerName = names[dealerIndex];
      await showInfoDialog(
        context,
        title: 'Willekeurige deler',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(
              builder: (context) {
                final style = Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold);
                final iconSize = (style?.fontSize ?? 28) * 1.1;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Symbols.playing_cards, size: iconSize),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        dealerName,
                        textAlign: TextAlign.center,
                        style: style,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'is geloot om als eerste te delen.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    final notifier = ref.read(calculatorProvider.notifier);
    notifier.startNewGame(names: names, dealerIndex: dealerIndex);
    final session = notifier.buildSession();
    if (session != null) {
      await ref.read(gameHistoryProvider.notifier).saveGame(session);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const CalculatorScreen(),
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
        lowerNames.toSet().length == 4;

    return Scaffold(
      appBar: AppBar(title: const Text('Nieuw spel')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
          // ---- Player names ----
          Text('Spelers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Sleep om de volgorde te wijzigen.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PlayerListField(
            controllers: _controllers,
            focusNodes: _focusNodes,
            suggestions: suggestions,
            onReorder: _handleReorder,
            onSubmitted: _handleFieldSubmitted,
          ),

          const SizedBox(height: 32),

          // ---- Dealer for first game ----
          Text(
            'Deler eerste spel',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'De speler links van de deler kiest het eerste spel.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DealerDropdownField(
            controllers: _controllers,
            value: _dealerIndex,
            hintText: 'Willekeurige deler',
            onChanged: (v) => setState(() => _dealerIndex = v),
            onClear: () => setState(() => _dealerIndex = null),
          ),

          const SizedBox(height: 48),

          // ---- Start button ----
          FilledButton.icon(
            icon: const Icon(Symbols.play_arrow),
            label: const Text('Start spel'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: canStart ? _handleStart : null,
          ),
          ],
        ),
      ),
    );
  }
}

