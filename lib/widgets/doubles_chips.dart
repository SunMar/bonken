import 'package:flutter/material.dart';

import '../models/double_matrix.dart';
import '../utils.dart';

/// A compact row of doubles chips for a round, e.g.
/// [primaryChip "A × B"] [tertiaryChip "C ×× D"]
/// Renders nothing when there are no active doubles.
class DoublesChips extends StatelessWidget {
  const DoublesChips({required this.doubles, required this.names, super.key});

  final DoubleMatrix doubles;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    const pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final redoubleBg = redoubleContainer(cs, brightness);
    final onRedoubleBg = onRedoubleContainer(cs, brightness);
    final chips = <Widget>[];

    for (final (a, b) in pairs) {
      final state = doubles.stateFor(a, b);
      if (state == DoubleState.none) continue;
      final initiator = doubles.initiatorFor(a, b) ?? a;
      final other = initiator == a ? b : a;
      final label = state == DoubleState.redoubled
          ? '${names[initiator]} ×× ${names[other]}'
          : '${names[initiator]} × ${names[other]}';
      final bg = state == DoubleState.redoubled
          ? redoubleBg
          : cs.primaryContainer;
      final fg = state == DoubleState.redoubled
          ? onRedoubleBg
          : cs.onPrimaryContainer;
      if (chips.isNotEmpty) chips.add(const SizedBox(width: 4));
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(spacing: 4, runSpacing: 4, children: chips),
    );
  }
}
