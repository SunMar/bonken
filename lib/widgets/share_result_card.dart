import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_session.dart';
import '../models/player.dart';
import '../models/round_record.dart';
import '../state/calculator_provider.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';

/// Embedded Bonken icon shown on the share card. Pre-cached before an
/// off-screen capture (which only waits one frame — too short for a cold asset
/// decode) so the first share never captures a blank icon.
const String shareIconAsset = 'assets/icon/icon_bonken_share.png';

/// Players ranked highest score first for the share views. Ties keep the
/// players' seat (display) order so the output is deterministic across renders
/// and app restarts — Bonken has no rule-level tiebreak, this is purely for a
/// stable list order.
List<({String name, int score, int seat})> rankScores(
  List<RoundRecord> history,
  List<Player> displayedPlayers,
) {
  final totals = cumulativeTotals(history, displayedPlayers);
  return [
    for (int i = 0; i < displayedPlayers.length; i++)
      (name: displayedPlayers[i].name, score: totals[i], seat: i),
  ]..sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.seat.compareTo(b.seat);
  });
}

/// Builds the plain-text share payload from already-ranked [entries] (highest
/// first). Pure (no provider access) so it is unit-testable; the top score gets
/// the 🏆 (ties shared).
String buildShareText({
  String? gameName,
  required DateTime scoredAt,
  required List<({String name, int score, int seat})> entries,
}) {
  final maxScore = entries.isEmpty ? 0 : entries.first.score;
  final lines = [
    'Bonken uitslag',
    ?gameName,
    formatDate(scoredAt),
    for (final e in entries)
      '${e.name}  ${e.score} pt${e.score == maxScore ? ' 🏆' : ''}',
  ];
  return lines.join('\n');
}

/// The result artifact rendered off-screen and captured as a PNG for image
/// sharing. A flat `Card` (no shadow — the capture is transparent) with the
/// Bonken icon, an optional game name + date, and the ranked score table with
/// the leader(s) highlighted.
class ShareResultCard extends ConsumerWidget {
  const ShareResultCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (history, displayedPlayers, scoredAt, gameName) = ref.watch(
      activeSessionProvider.select(
        (a) => (a.history, a.displayedPlayers, a.scoredAt, a.gameName),
      ),
    );

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final entries = rankScores(history, displayedPlayers);
    // Single max-score derivation (mirrors buildShareText, with the empty
    // guard) — the decoration and trophy both read the one `isWinner` per row.
    final maxScore = entries.isEmpty ? 0 : entries.first.score;

    return Card(
      // Flat: the capture is a transparent PNG, so a drop shadow would paint
      // onto transparency as a grey halo. The surface colour follows the
      // current theme (dark mode → dark card) — intentional.
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(shareIconAsset, width: 24, height: 24),
                ),
                const SizedBox(width: 8),
                Text(
                  'Uitslag',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (gameName != null) ...[
              Text(
                gameName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatDate(scoredAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ] else
              Text(
                formatDate(scoredAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: IntrinsicColumnWidth(),
                2: IntrinsicColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final entry in entries)
                  _shareRow(context, entry, isWinner: entry.score == maxScore),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One score row; [isWinner] gates both the highlight background and the
  /// trophy so the two can't fall out of sync.
  TableRow _shareRow(
    BuildContext context,
    ({String name, int score, int seat}) entry, {
    required bool isWinner,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TableRow(
      decoration: isWinner
          ? BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 6,
            end: 16,
            top: 3,
            bottom: 3,
          ),
          child: Text(entry.name, style: theme.textTheme.bodyLarge),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 4, top: 3, bottom: 3),
          child: Text(
            '${entry.score} pt',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: scoreColor(entry.score, context),
            ),
            textAlign: TextAlign.end,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 4,
            end: 6,
            top: 3,
            bottom: 3,
          ),
          child: isWinner
              ? Icon(
                  Symbols.emoji_events,
                  size: 16,
                  fill: 1,
                  color: cs.onTertiaryContainer,
                  semanticLabel: 'Winnaar',
                )
              : const SizedBox(width: 16),
        ),
      ],
    );
  }
}
