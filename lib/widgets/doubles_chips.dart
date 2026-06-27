import 'package:flutter/material.dart';

import '../models/double_matrix.dart';
import '../models/game_mechanics.dart' show doublingTurnIndex;
import '../models/player.dart';
import '../theme/app_theme_extensions.dart';
import 'double_state_chip.dart';

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
    required this.players,
    required this.chooserIndex,
    super.key,
  });

  final DoubleMatrix doubles;
  final List<Player> players;
  final int chooserIndex;

  @override
  Widget build(BuildContext context) {
    const pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
    final dc = DoubleStateColors.of(context);

    // Collect active pairs first so we can sort them.
    // Tuple: (initiatorIdx, otherIdx, initiatorTurn, otherTurn)
    final active = <(int, int, int, int)>[];
    for (final (a, b) in pairs) {
      final state = doubles.stateFor(players[a].id, players[b].id);
      if (state == DoubleState.none) continue;
      final initiatorId =
          doubles.initiatorFor(players[a].id, players[b].id) ?? players[a].id;
      final initiator = players.indexWhere((p) => p.id == initiatorId);
      final other = initiator == a ? b : a;
      final initiatorTurn = doublingTurnIndex(initiator, chooserIndex);
      final otherTurn = doublingTurnIndex(other, chooserIndex);
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
      final state = doubles.stateFor(players[initiator].id, players[other].id);
      final initiatorName = players[initiator].name;
      final otherName = players[other].name;
      // Visible label stays the compact glyph form; the spoken label uses the
      // app's own doubling terms (the picker legend: "dubbelt" / "gaat terug")
      // so assistive tech never reads the bare "×"/"××" literally.
      final (
        String label,
        String semanticLabel,
      ) = state == DoubleState.redoubled
          ? (
              '$initiatorName ×× $otherName',
              '$initiatorName dubbelt $otherName, $otherName gaat terug',
            )
          : (
              '$initiatorName × $otherName',
              '$initiatorName dubbelt $otherName',
            );
      chips.add(
        DoubleStateChip(
          label: label,
          semanticLabel: semanticLabel,
          background: dc.backgroundFor(state)!,
          foreground: dc.foregroundFor(state)!,
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
