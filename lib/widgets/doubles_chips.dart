import 'package:flutter/material.dart';

import '../models/double_matrix.dart';
import '../utils.dart';

/// A compact row of doubles chips for a round, e.g.
/// [primaryChip "A × B"] [tertiaryChip "C ×× D"]
/// Renders nothing when there are no active doubles.
///
/// Chips are ordered by the initiator's position in the doubling turn order
/// (chooser+1 first … chooser last) so they read in the same order players
/// were given the option to double on the input screen.
class DoublesChips extends StatelessWidget {
  const DoublesChips({
    required this.doubles,
    required this.names,
    required this.chooserIndex,
    super.key,
  });

  final DoubleMatrix doubles;
  final List<String> names;
  final int chooserIndex;

  @override
  Widget build(BuildContext context) {
    const pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final redoubleBg = redoubleContainer(cs, brightness);
    final onRedoubleBg = onRedoubleContainer(cs, brightness);

    // Collect active pairs first so we can sort them.
    // Tuple: (initiator, other, initiatorTurn, otherTurn)
    final active = <(int, int, int, int)>[];
    for (final (a, b) in pairs) {
      final state = doubles.stateFor(a, b);
      if (state == DoubleState.none) continue;
      final initiator = doubles.initiatorFor(a, b) ?? a;
      final other = initiator == a ? b : a;
      // Turn 0 = first to double (chooser+1), turn 3 = chooser themselves.
      final initiatorTurn = (initiator - chooserIndex - 1 + 4) % 4;
      final otherTurn = (other - chooserIndex - 1 + 4) % 4;
      active.add((initiator, other, initiatorTurn, otherTurn));
    }
    // Primary: initiator's turn position; secondary: other's turn position
    // so the chip order matches the input screen's target list ordering for
    // each initiator.
    active.sort((x, y) {
      final byInit = x.$3.compareTo(y.$3);
      if (byInit != 0) return byInit;
      return x.$4.compareTo(y.$4);
    });

    final chips = <Widget>[];
    for (final (initiator, other, _, _) in active) {
      final state = doubles.stateFor(initiator, other);
      final label = state == DoubleState.redoubled
          ? '${names[initiator]} ×× ${names[other]}'
          : '${names[initiator]} × ${names[other]}';
      final bg = state == DoubleState.redoubled
          ? redoubleBg
          : cs.primaryContainer;
      final fg = state == DoubleState.redoubled
          ? onRedoubleBg
          : cs.onPrimaryContainer;
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
