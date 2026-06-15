import 'package:flutter/material.dart';

import 'theme/app_theme_extensions.dart';

/// Looks up an enum value by its [Enum.name], returning [fallback] when
/// [name] is null or no value matches. Used by provider load helpers and
/// [GameSession.fromJson] so the fallback logic is written once.
T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Title for every "discard your edits" confirmation dialog.
const String kDiscardChangesTitle = 'Wijzigingen verwerpen';

/// Body text reused by every "discard your edits" confirmation dialog
/// (round input screen, edit-game screen, …).
const String kDiscardChangesMessage = 'Je wijzigingen gaan verloren.';

/// Title for the "discard new-game input" confirmation dialog.
const String kDiscardInputTitle = 'Invoer verwerpen';

/// Body text for the "discard new-game input" confirmation dialog.
const String kDiscardInputMessage = 'Je invoer gaat verloren.';

/// Label for every discard confirm button, tooltip, and action.
const String kDiscardLabel = 'Verwerpen';

/// Label for every save button and confirm action.
const String kSaveLabel = 'Opslaan';

/// Title used both for the "another game is still pending" info dialog
/// (game screen) and for the "discard the in-progress round" confirm
/// dialog (round input screen).
const String kRoundIncompleteTitle = 'Ronde niet afgerond';

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

Color scoreColorPositive(BuildContext context) =>
    ScoreColors.of(context).positive;
Color scoreColorNegative(BuildContext context) =>
    ScoreColors.of(context).negative;
Color scoreColorNeutral(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Material 3 disabled-content color: `onSurface` at 38% alpha.
///
/// `0.38` is the official M3 disabled-content opacity from the spec
/// (m3.material.io → states → disabled). Use this for text, icons and
/// other foreground content drawn on top of a surface when their
/// associated control is disabled. Centralised so the alpha value isn't
/// sprinkled across screens.
Color disabledOnSurface(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.38);

/// Shared [MenuItemButton] / [SubmenuButton] style for menu anchors.
///
/// Adds 16 px of horizontal padding so the [TextButton]-derived
/// [MenuItemButton] gets a comfortable popup-menu rhythm instead of its
/// default tight padding. Referenced by the theme menu (`ThemeMenuButton`) and
/// any future [MenuAnchor], so their item density stays in sync.
final ButtonStyle kMenuItemButtonStyle = MenuItemButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 16),
);

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
