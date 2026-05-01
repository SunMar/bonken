import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // State is already reset by the caller (StartScreen) before pushing this
    // route, so no reset is needed here.
  }

  @override
  void dispose() {
    // If the user navigated back without starting, clear the provider so the
    // next visit always opens with a blank form.
    if (!_started) {
      ref.read(calculatorProvider.notifier).reset();
    }
    super.dispose();
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
          const SizedBox(height: 16),
          for (int i = 0; i < playerCount; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _NameField(
              index: i,
              initialName: state.playerNames[i],
              suggestions: suggestions,
              takenNames: {
                for (int j = 0; j < playerCount; j++)
                  if (j != i && trimmedNames[j].isNotEmpty) trimmedNames[j],
              },
              notifier: notifier,
            ),
          ],

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
    required this.initialName,
    required this.suggestions,
    required this.takenNames,
    required this.notifier,
  });

  final int index;
  final String initialName;
  final List<String> suggestions;
  final Set<String> takenNames;
  final CalculatorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      // Rebuild when other players' names change so the cached options list
      // is recomputed (Autocomplete only re-runs optionsBuilder on text edits).
      // takenNames excludes our own name, so typing here doesn't reset us.
      key: ValueKey('field-$index-${takenNames.join("|")}'),
      initialValue: TextEditingValue(text: initialName),
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
      onSelected: (value) => notifier.setPlayerName(index, value),
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
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Speler ${index + 1}',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => notifier.setPlayerName(index, v),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
    );
  }
}
