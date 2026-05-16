import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_session.dart';
import '../utils.dart';

/// A scoreboard card that shows the cumulative scores for a single
/// Bonken game (either an in-progress / finished session in the home
/// screen's history list, or the live session on the score-input
/// screen).
///
/// The card always has the same shape:
///
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ [progress glyph] [headerLabel]    [trailing]│
/// │                                             │
/// │ [chip]   [chip]   [chip]   [chip]           │
/// └─────────────────────────────────────────────┘
/// ```
///
/// * The progress glyph is derived from [roundsPlayed] (an animated
///   `clock_loader_*` series, replaced by a filled `check_circle` once
///   the game is finished).
/// * [headerLabel] is the widget shown right of the glyph (e.g. the
///   game's date on the home screen, or the literal "Tussenstand" /
///   "Eindstand" on the in-game view). It is wrapped in an [Expanded]
///   so it pushes [headerTrailing] to the far right and ellipsizes
///   long labels instead of overflowing.
/// * [headerTrailing] is shown on the far right of the header (e.g. the
///   date on the in-game view, or a delete `IconButton` on the home
///   screen). Pass `null` to omit it.
/// * [onTap] makes the entire card tappable via an [InkWell]. When
///   `null` the card has no ripple feedback and no tap target — this
///   is intentional, so a non-tappable card never *looks* tappable.
class ScoreboardCard extends StatelessWidget {
  const ScoreboardCard({
    super.key,
    required this.roundsPlayed,
    required this.playerNames,
    required this.scores,
    required this.winners,
    required this.headerLabel,
    this.headerTrailing,
    this.onTap,
    this.margin,
  });

  /// Number of completed rounds (0..[GameSession.totalRounds]).
  final int roundsPlayed;

  /// Player names in seat order. Length must equal [scores].length.
  final List<String> playerNames;

  /// Cumulative score per player in seat order.
  final List<int> scores;

  /// Indices into [playerNames] / [scores] of the winning player(s).
  /// Pass an empty list while a game is mid-flight — winners shouldn't
  /// claim the crown until the game is finished.
  final List<int> winners;

  /// Label shown immediately right of the progress glyph (after a
  /// 6-pixel gap). Wrapped in an [Expanded] internally so it absorbs
  /// the free space and pushes [headerTrailing] to the far right.
  final Widget headerLabel;

  /// Optional widget shown on the far right of the header. Typically a
  /// date `Text` or a trailing `IconButton`.
  final Widget? headerTrailing;

  /// If non-null, the card becomes tappable (with an [InkWell] ripple).
  /// When null, the card is purely informational.
  final VoidCallback? onTap;

  /// Outer card margin. Defaults to the standard `Card` margin (i.e.
  /// whatever `CardTheme.margin` resolves to — `EdgeInsets.all(4)` on
  /// stock Material 3).
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    assert(playerNames.length == scores.length);
    assert(
      winners.every((i) => i >= 0 && i < playerNames.length),
      'winners must be valid indices into playerNames/scores',
    );
    final cs = Theme.of(context).colorScheme;
    final isFinished = roundsPlayed >= GameSession.totalRounds;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFinished
                    ? Symbols.check_circle
                    : _scoreboardProgressIcon(roundsPlayed),
                // Filled check rhymes with a fully-filled clock_loader,
                // turning the in-progress → finished transition into the
                // last frame of the same loader animation. Monochrome on
                // both states — completion is carried by the glyph, not
                // by colour.
                fill: isFinished ? 1 : 0,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              // Expanded (not Flexible) so the label absorbs the free
              // space and pushes [headerTrailing] to the far right.
              // The label still ellipsizes via the caller's
              // `overflow: ellipsis`.
              Expanded(child: headerLabel),
              if (headerTrailing != null) ...[
                const SizedBox(width: 8),
                headerTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < playerNames.length; i++)
                // Symmetric 2 px horizontal padding per slot ⇒ 4 px
                // between adjacent chips and 2 px on the outer edges,
                // which combines with the Card's 16 px padding to give
                // a balanced left/right gutter (no asymmetric tail
                // after the last chip).
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _PlayerScoreChip(
                      name: playerNames[i],
                      score: scores[i],
                      isWinner: winners.contains(i),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return Card(
      margin: margin,
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// Picks the closest `clock_loader_*` glyph for an in-progress game.
///
/// Material Symbols ships a six-step loader series whose pie-style fill
/// reads naturally as "X of N done" — perfect for Bonken's fixed
/// [GameSession.totalRounds]-round arc. [ScoreboardCard] renders
/// [Symbols.check_circle] (with `fill: 1`) for the finished state so the
/// in-progress → finished transition completes the same animation.
IconData _scoreboardProgressIcon(int roundsPlayed) {
  final pct = (roundsPlayed / GameSession.totalRounds * 100).round();
  if (pct < 15) return Symbols.clock_loader_10;
  if (pct < 30) return Symbols.clock_loader_20;
  if (pct < 50) return Symbols.clock_loader_40;
  if (pct < 70) return Symbols.clock_loader_60;
  if (pct < 90) return Symbols.clock_loader_80;
  return Symbols.clock_loader_90;
}

/// Single player column inside the scoreboard row: name + score, with an
/// optional winner highlight (`tertiaryContainer` pill background,
/// trophy icon, bold name). Private because callers always go through
/// [ScoreboardCard]; the chip layout is meaningless on its own.
class _PlayerScoreChip extends StatelessWidget {
  const _PlayerScoreChip({
    required this.name,
    required this.score,
    required this.isWinner,
  });

  final String name;
  final int score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Column(
        children: [
          // Name row: trophy sits inline before the winner's name
          // (instead of stacked above) so winner and non-winner chips
          // share the same vertical rhythm — name and score always land
          // on the same baselines across the row.
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isWinner) ...[
                Icon(
                  Symbols.emoji_events,
                  size: 14,
                  color: cs.onTertiaryContainer,
                  fill: 1,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: isWinner ? FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatScore(score),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: scoreColor(score, context),
            ),
          ),
        ],
      ),
    );

    if (!isWinner) return inner;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: inner,
    );
  }
}
