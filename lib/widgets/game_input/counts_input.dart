import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Displays four stepper rows (one per player) for games where each player's
/// count must be entered and all four must sum to [total].
class CountsStepper extends StatelessWidget {
  const CountsStepper({
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

  void _applyDelta(int index, int delta) {
    final updated = List<int>.from(counts);
    updated[index] += delta;
    onCountsChanged(updated);
  }

  void _increment(int index) => _applyDelta(index, 1);

  void _decrement(int index) => _applyDelta(index, -1);

  void _addRemaining(int index, int remaining) {
    if (remaining <= 0) return;
    _applyDelta(index, remaining);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      counts.length == playerNames.length,
      'counts (${counts.length}) and playerNames (${playerNames.length}) '
      'must have the same length',
    );
    final theme = Theme.of(context);
    final sum = _sum;
    final remaining = total - sum;
    final isComplete = sum == total;

    // Per-row stepper buttons (-, +, all-remaining). Keep the standard 48dp
    // tap target (a11y `androidTapTargetGuideline`) but zero internal padding
    // so the icons sit as tight as the 48dp minimum allows — installed once
    // here instead of per-button.
    final stepperTheme = theme.copyWith(
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
        ),
      ),
    );

    return Theme(
      data: stepperTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < counts.length; i++)
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
      ),
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
            icon: const Icon(Symbols.remove_circle),
            onPressed: canDecrement ? onDecrement : null,
            tooltip: 'Minder',
          ),
          // Ghost-text Stack: an invisible string that renders at the widest
          // possible width sets the column size; the actual count overlays it.
          // This prevents the adjacent buttons from shifting when the count
          // changes (e.g. 9→10) or when the system font scale changes.
          Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0,
                  // '12' is the widest of the reachable values 10–13 in Roboto:
                  //   '2' > '0' = '3' >> '1' (measured in pixels).
                  // So '12' (1+2) > '10'='13' (1+0 = 1+3) > '11' (1+1).
                  // Also handles the 9→10 digit-count jump.
                  // Revisit if a game ever adds a per-player total > 13 or if
                  // the body font changes.
                  child: Text(
                    '12',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Text(
                '$count',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Symbols.add_circle),
            onPressed: canIncrement ? onIncrement : null,
            tooltip: 'Meer',
          ),
          IconButton(
            icon: const Icon(Symbols.expand_circle_right),
            onPressed: canIncrement ? onAddRemaining : null,
            tooltip: 'Alle resterende',
          ),
        ],
      ),
    );
  }
}
