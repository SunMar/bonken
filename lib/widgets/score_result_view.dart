import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/double_matrix.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/score_result.dart';
import '../utils.dart';
import 'doubles_chips.dart';

/// Displays the per-player score outcome of a calculated mini-game round.
class ScoreResultView extends StatelessWidget {
  const ScoreResultView({
    required this.result,
    required this.game,
    required this.players,
    required this.chooserIndex,
    this.doubles,
    this.isPartial = false,
    this.showHeader = true,
    super.key,
  });

  final ScoreResult result;
  final MiniGame game;
  final List<Player> players;
  final DoubleMatrix? doubles;
  final int chooserIndex;

  /// When true, shows a pending icon and dimmed opacity, indicating the score
  /// is not yet final.
  final bool isPartial;

  /// When true, shows the 'Score' header row with status icon.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Winner(s): highest score among players. Only shown when complete.
    final scores = [for (final p in players) result.scores[p.id] ?? 0];
    final best = scores.reduce((a, b) => a > b ? a : b);
    final winners = isPartial
        ? <int>[]
        : [
            for (int i = 0; i < scores.length; i++)
              if (scores[i] == best) i,
          ];

    return Opacity(
      opacity: isPartial ? 0.7 : 1.0,
      child: Card(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHeader) ...[
                Text('Score', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
              ],
              for (int i = 0; i < players.length; i++)
                _ScoreRow(
                  name: players[i].name,
                  score: result.scores[players[i].id] ?? 0,
                  isWinner: winners.contains(i),
                ),
              if (doubles?.hasAnyDouble == true) ...[
                const SizedBox(height: 8),
                DoublesChips(
                  doubles: doubles!,
                  players: players,
                  chooserIndex: chooserIndex,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.name,
    required this.score,
    this.isWinner = false,
  });

  final String name;
  final int score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final color = scoreColor(score, context);
    final label = formatScore(score);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (isWinner) ...[
            Icon(Symbols.emoji_events, size: 16, color: cs.primary, fill: 1),
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 20),
          Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
