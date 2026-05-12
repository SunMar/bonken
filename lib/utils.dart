import 'package:flutter/material.dart';

import 'theme/app_theme_extensions.dart';

/// Maximum number of characters allowed in a player name.
const int kPlayerNameMaxLength = 20;

String formatDate(DateTime dt) {
  const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  const months = [
    'jan',
    'feb',
    'mrt',
    'apr',
    'mei',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
  final day = days[dt.weekday - 1];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$day ${dt.day} ${months[dt.month - 1]} ${dt.year}  $h:$m';
}

String formatScore(int score) => score > 0 ? '+$score' : '$score';

/// Tint for a player's cumulative or per-round score, based on its sign.
///
/// Reads the [ScoreColors] theme extension; falls back to the
/// brightness-appropriate static if unavailable (e.g. unthemed test
/// widgets).
Color scoreColor(int score, BuildContext context) {
  if (score == 0) return scoreColorNeutral(context);
  return score > 0 ? scoreColorPositive(context) : scoreColorNegative(context);
}

Color scoreColorPositive(BuildContext context) => _scoreColors(context).positive;
Color scoreColorNegative(BuildContext context) => _scoreColors(context).negative;
Color scoreColorNeutral(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

ScoreColors _scoreColors(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<ScoreColors>() ??
      (theme.brightness == Brightness.dark
          ? ScoreColors.dark
          : ScoreColors.light);
}

/// Recomputes [target]'s position after an item is moved from [oldIdx] to
/// [newIdx] in a list (using the same convention as [ReorderableListView]).
///
/// Returns the new index of whatever was previously at [target].  When
/// [target] equals [oldIdx], the returned value is the new index of the
/// moved item (i.e. [newIdx], normalised).
int adjustIndexAfterReorder(int oldIdx, int newIdx, int target) {
  if (target == oldIdx) return newIdx;
  var t = target;
  if (oldIdx < t) t -= 1;
  if (newIdx <= t) t += 1;
  return t;
}
