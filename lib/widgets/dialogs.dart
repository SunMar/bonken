import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../utils.dart';

/// Shows a yes/no confirmation [AlertDialog] and resolves to:
///
/// * `true` — user pressed the confirm button
/// * `false` — user pressed cancel
/// * `null` — user dismissed the dialog (tap outside / back button)
///
/// When [destructive] is true, the confirm button uses the theme's error
/// color, intended for actions that discard data or delete things.
///
/// Pass `Widget content` instead of [contentText] for custom layouts.
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? contentText,
  Widget? content,
  String confirmLabel = 'OK',
  String cancelLabel = 'Annuleren',
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      // Material 3 confirmation dialogs use a `TextButton` for the affirmative
      // action.  For destructive variants the label is tinted with the
      // theme's error colour instead of swapping in a filled red button — the
      // chromeless treatment keeps the dialog calm while still flagging the
      // action as dangerous.
      return AlertDialog(
        title: Text(title),
        content: content ?? Text(contentText!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          TextButton(
            style: destructive
                ? TextButton.styleFrom(foregroundColor: cs.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

/// Shows the standard destructive discard-confirmation dialog when [dirty] and
/// returns whether the caller should proceed (i.e. pop). Returns `true`
/// immediately when not [dirty], so the form is only guarded when it has
/// unsaved work.
///
/// The caller keeps the `pop` and the post-await `mounted` check local so the
/// use-of-context-after-await lint stays at the call site. Always uses the
/// [kDiscardLabel] confirm button and the destructive (error-tinted) treatment.
Future<bool> confirmDiscard(
  BuildContext context, {
  required bool dirty,
  required String title,
  required String message,
}) async {
  if (!dirty) return true;
  final confirmed = await showConfirmDialog(
    context,
    title: title,
    contentText: message,
    confirmLabel: kDiscardLabel,
    destructive: true,
  );
  return confirmed == true;
}

/// Shows a single-button informational [AlertDialog].
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  String? contentText,
  Widget? content,
  String buttonLabel = 'OK',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content ?? Text(contentText!),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}

/// How a dealer was picked, used by [showDealerAnnouncementDialog] to
/// choose the sentence shown below the player's name.
enum DealerAnnouncementKind {
  /// Picked at random (start of game, or mid-game "Willekeurig" reroll).
  random('is geloot als deler.'),

  /// Rotated to the next seat after a completed round.
  next('is de volgende deler.');

  const DealerAnnouncementKind(this.sentence);

  /// The trailing sentence rendered after `<dealerName> `, with the
  /// leading space and trailing period included.
  final String sentence;
}

/// Shows the dealer-announcement info dialog used when the dealer is picked
/// at random or rotated automatically.
///
/// The dialog title is the literal label "Deler"; the content is the data
/// point itself (icon + player name) followed by a small grey sentence
/// describing how this player became dealer (e.g. "is geloot als deler.").
Future<void> showDealerAnnouncementDialog(
  BuildContext context, {
  required String dealerName,
  DealerAnnouncementKind kind = DealerAnnouncementKind.random,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final nameStyle = theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      );
      final iconSize = (nameStyle?.fontSize ?? 22) * 1.1;
      return AlertDialog(
        title: const Text('Deler', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Symbols.playing_cards, size: iconSize),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    dealerName,
                    textAlign: TextAlign.center,
                    style: nameStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              kind.sentence,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
