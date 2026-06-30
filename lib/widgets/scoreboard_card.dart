import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_session.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';

/// A scoreboard card that shows the cumulative scores for a single
/// Bonken game (either an in-progress / finished session in the home
/// screen's history list, or the live session on the score-input
/// screen).
///
/// The header shows a progress glyph, then [gameName] as a bold title
/// with [updatedAt] as a muted subtitle (or [updatedAt] alone when
/// [gameName] is null), then an optional [headerTrailing] widget.
/// [onTap] makes the whole card tappable; pass `null` for a static card.
class ScoreboardCard extends StatelessWidget {
  const ScoreboardCard({
    super.key,
    required this.roundsPlayed,
    required this.playerNames,
    required this.scores,
    required this.winners,
    required this.scoredAt,
    this.gameName,
    this.headerTrailing,
    this.onTap,
    this.tapSemanticLabel,
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

  /// Shown as a muted subtitle (or as the sole header line when [gameName]
  /// is null).
  final DateTime scoredAt;

  /// Optional game name shown as the primary header line above [scoredAt].
  /// Never the empty string — pass null to show only the date.
  final String? gameName;

  /// Optional widget shown on the far right of the header. Typically a
  /// trailing `IconButton`.
  final Widget? headerTrailing;

  /// If non-null, the card becomes tappable (with an [InkWell] ripple).
  /// When null, the card is purely informational.
  final VoidCallback? onTap;

  /// Accessible label for the whole card when [onTap] is set (announced as a
  /// button). Callers that set [onTap] should provide this so screen readers
  /// identify the card; ignored when [onTap] is null.
  final String? tapSemanticLabel;

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isFinished = roundsPlayed >= GameSession.totalRounds;

    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final Widget label = gameName != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                gameName!,
                style: titleStyle,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                formatDate(scoredAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )
        : Text(
            formatDate(scoredAt),
            style: titleStyle,
            overflow: TextOverflow.ellipsis,
          );

    final tappable = onTap != null;

    // Decorative content (progress glyph, title/date, score chips) is excluded
    // from semantics when the card is tappable: [tapSemanticLabel] already names
    // the whole card, so this avoids double-announcing it. Pointer events need no
    // special handling — the [InkWell] below *wraps* this content (it is an
    // ancestor, not a sibling behind it), so a tap on any part of it, including
    // the glyph-bearing title [Text], is already in the InkWell's hit path.
    Widget decorative(Widget child) =>
        tappable ? ExcludeSemantics(child: child) : child;

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              decorative(
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
                  size: 24,
                  color: cs.onSurfaceVariant,
                  semanticLabel: isFinished ? 'Afgerond spel' : 'Lopend spel',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: decorative(label)),
              if (headerTrailing != null) ...[
                const SizedBox(width: 8),
                headerTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          decorative(
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
          ),
        ],
      ),
    );

    return Card(
      margin: margin,
      child: !tappable
          ? body
          // The whole card is one openable button. The [InkWell] *wraps* the
          // [body], so it is an ancestor of every part of it: a tap anywhere —
          // including on the title text, which would otherwise absorb the hit —
          // is already in the InkWell's hit path. Decorative content is
          // ExcludeSemantics'd so only [tapSemanticLabel] is announced;
          // [headerTrailing]'s own button(s) sit inline and win their own taps
          // (an inner button beats the surrounding InkWell in the gesture arena),
          // staying separately reachable to assistive tech.
          : Semantics(
              button: true,
              label: tapSemanticLabel,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: body,
              ),
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

    final inner = MergeSemantics(
      child: Padding(
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
                    semanticLabel: 'Winnaar',
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
