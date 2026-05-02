import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/mini_game.dart';

/// Displays four stepper rows (one per player) for games where each player's
/// count must be entered and all four must sum to [total].
class CountsInput extends StatelessWidget {
  const CountsInput({
    required this.playerNames,
    required this.counts,
    required this.total,
    required this.unitLabel,
    required this.onCountsChanged,
    super.key,
  });

  final List<String> playerNames;
  final List<int> counts;
  final int total;

  /// Dutch unit shown in the total row (e.g. 'slagen', 'harten').
  final String unitLabel;
  final ValueChanged<List<int>> onCountsChanged;

  int get _sum => counts.fold(0, (a, b) => a + b);

  void _increment(int index) {
    final updated = List<int>.from(counts);
    updated[index]++;
    onCountsChanged(updated);
  }

  void _decrement(int index) {
    final updated = List<int>.from(counts);
    updated[index]--;
    onCountsChanged(updated);
  }

  void _addRemaining(int index, int remaining) {
    if (remaining <= 0) return;
    final updated = List<int>.from(counts);
    updated[index] += remaining;
    onCountsChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sum = _sum;
    final remaining = total - sum;
    final isComplete = sum == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < playerCount; i++)
          _PlayerCountRow(
            name: playerNames[i],
            count: counts[i],
            canIncrement: remaining > 0,
            canDecrement: counts[i] > 0,
            onIncrement: () => _increment(i),
            onDecrement: () => _decrement(i),
            onAddRemaining: () => _addRemaining(i, remaining),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Totaal: $sum / $total $unitLabel',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isComplete
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayerCountRow extends StatelessWidget {
  const _PlayerCountRow({
    required this.name,
    required this.count,
    required this.canIncrement,
    required this.canDecrement,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAddRemaining,
  });

  final String name;
  final int count;
  final bool canIncrement;
  final bool canDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onAddRemaining;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(name, style: Theme.of(context).textTheme.bodyLarge),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.remove_circle),
            onPressed: canDecrement ? onDecrement : null,
            tooltip: 'Minder',
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.add_circle),
            onPressed: canIncrement ? onIncrement : null,
            tooltip: 'Meer',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Symbols.expand_circle_right),
            onPressed: canIncrement ? onAddRemaining : null,
            tooltip: 'Alle resterende',
          ),
        ],
      ),
    );
  }
}
