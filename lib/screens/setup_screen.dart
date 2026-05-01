import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mini_game.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import 'calculator_screen.dart';

/// Second screen: enter player names and pick the dealer for the first game.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _started = false;
  late final List<FocusNode> _focusNodes;
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final names = ref.read(calculatorProvider).playerNames;
    _controllers = [
      for (int i = 0; i < playerCount; i++)
        TextEditingController(text: names[i]),
    ];
    _focusNodes = List.generate(playerCount, (i) {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) _commitSlot(i);
      });
      return node;
    });
    // State is already reset by the caller (StartScreen) before pushing this
    // route, so no reset is needed here.
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    // If the user navigated back without starting, clear the provider so the
    // next visit always opens with a blank form.
    if (!_started) {
      ref.read(calculatorProvider.notifier).reset();
    }
    super.dispose();
  }

  /// Pushes the current controller text for [i] into the provider when it
  /// differs from the stored value.
  void _commitSlot(int i) {
    final text = _controllers[i].text;
    if (text != ref.read(calculatorProvider).playerNames[i]) {
      ref.read(calculatorProvider.notifier).setPlayerName(i, text);
    }
  }

  void _commitAllSlots() {
    for (int i = 0; i < playerCount; i++) {
      _commitSlot(i);
    }
  }

  /// Called when the user presses Enter on the slot at [index].
  /// If the next slot exists and is still empty, focus it so the user can
  /// keep typing.  Otherwise unfocus the current field so the cursor
  /// disappears.
  void _handleFieldSubmitted(int index) {
    _commitSlot(index);
    final next = index + 1;
    if (next < playerCount && _controllers[next].text.trim().isEmpty) {
      _focusNodes[next].requestFocus();
      return;
    }
    _focusNodes[index].unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calculatorProvider);
    final notifier = ref.read(calculatorProvider.notifier);
    // Watch history so suggestions update if it finishes loading after this
    // widget is first built.
    final suggestions = ref
        .watch(gameHistoryProvider.notifier)
        .playerNameSuggestions;

    final trimmedNames = state.playerNames.map((n) => n.trim()).toList();
    final hasDuplicateNames =
        trimmedNames.where((n) => n.isNotEmpty).length !=
        trimmedNames.where((n) => n.isNotEmpty).toSet().length;
    final canStart =
        trimmedNames.every((n) => n.isNotEmpty) &&
        trimmedNames.toSet().length == 4 &&
        state.dealerChosen;

    return Scaffold(
      appBar: AppBar(title: const Text('Nieuw spel')),
      body: SafeArea(
        top: false,
        child: ListView(
          // Key on sessionId so Autocomplete widgets are recreated after reset().
          key: ValueKey(state.sessionId),
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
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              // Commit any pending edits first so the provider has the latest
              // text before we reorder it.
              _commitAllSlots();
              notifier.reorderPlayerNames(oldIndex, newIndex);
              // Sync controller texts to the new order.  This does not move
              // focus, so the field the user was editing keeps its caret.
              final newNames = ref.read(calculatorProvider).playerNames;
              for (int i = 0; i < playerCount; i++) {
                if (_controllers[i].text != newNames[i]) {
                  _controllers[i].value = TextEditingValue(
                    text: newNames[i],
                    selection: TextSelection.collapsed(
                      offset: newNames[i].length,
                    ),
                  );
                }
              }
            },
            children: [
              for (int i = 0; i < playerCount; i++)
                Padding(
                  key: ValueKey('player-slot-$i'),
                  padding: EdgeInsets.only(bottom: i < playerCount - 1 ? 12 : 0),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.drag_indicator,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _NameField(
                          index: i,
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          suggestions: suggestions,
                          takenNames: {
                            for (int j = 0; j < playerCount; j++)
                              if (j != i && trimmedNames[j].isNotEmpty)
                                trimmedNames[j],
                          },
                          onSubmitted: () => _handleFieldSubmitted(i),
                          isLast: i == playerCount - 1,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (hasDuplicateNames) ...[
            const SizedBox(height: 8),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ],

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
          DropdownButtonFormField<int>(
            initialValue: state.dealerChosen ? state.dealerIndex : null,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (int i = 0; i < playerCount; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    state.playerNames[i].trim().isNotEmpty
                        ? state.playerNames[i]
                        : 'Speler ${i + 1}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) notifier.setDealer(v);
            },
          ),

          const SizedBox(height: 48),

          // ---- Start button ----
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start spel'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: canStart
                ? () {
                    _commitAllSlots();
                    _started = true;
                    final notifier = ref.read(calculatorProvider.notifier);
                    notifier.initSession();
                    final session = notifier.buildSession();
                    if (session != null) {
                      ref.read(gameHistoryProvider.notifier).saveGame(session);
                    }
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const CalculatorScreen(),
                      ),
                    );
                  }
                : null,
          ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Autocomplete name field
// =============================================================================

class _NameField extends StatelessWidget {
  const _NameField({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.takenNames,
    required this.onSubmitted,
    required this.isLast,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final Set<String> takenNames;
  final VoidCallback onSubmitted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (textEditingValue) {
        if (suggestions.isEmpty) return const Iterable<String>.empty();
        final query = textEditingValue.text.toLowerCase();
        // Hide suggestions already chosen for other players.
        final available = suggestions.where((s) => !takenNames.contains(s));
        // Show all suggestions (sorted by frequency) when field is empty;
        // otherwise filter to those containing the typed text.
        if (query.isEmpty) return available;
        return available.where((s) => s.toLowerCase().contains(query));
      },
      onSelected: (value) {
        controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, idx) {
                  final option = options.elementAt(idx);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, ctrl, fn, onFieldSubmitted) {
        return Focus(
          // Intercept Tab so it behaves the same as the on-screen "Next"
          // action: commit + advance to the next empty slot (or unfocus).
          // Shift+Tab falls through to the default reverse focus traversal.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.tab &&
                !HardwareKeyboard.instance.isShiftPressed) {
              onFieldSubmitted();
              onSubmitted();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: ctrl,
            focusNode: fn,
            decoration: InputDecoration(
              labelText: 'Speler ${index + 1}',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: isLast
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: (_) {
              onFieldSubmitted();
              onSubmitted();
            },
          ),
        );
      },
    );
  }
}
