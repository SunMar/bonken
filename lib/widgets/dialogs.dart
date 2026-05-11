import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
  assert(
    contentText != null || content != null,
    'Provide either contentText or content',
  );
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

/// Shows a single-button informational [AlertDialog].
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  String? contentText,
  Widget? content,
  String buttonLabel = 'OK',
}) {
  assert(
    contentText != null || content != null,
    'Provide either contentText or content',
  );
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

/// Shows the "[dealerName]" info dialog used when the dealer is picked at
/// random or rotated automatically. The [title] indicates the context
/// (e.g. "Willekeurige deler" vs "Nieuwe deler").
Future<void> showDealerAnnouncementDialog(
  BuildContext context, {
  required String dealerName,
  String title = 'Willekeurige deler',
}) {
  return showInfoDialog(
    context,
    title: title,
    content: Builder(
      builder: (context) {
        final style = Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold);
        final iconSize = (style?.fontSize ?? 28) * 1.1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.playing_cards, size: iconSize),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                dealerName,
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ],
        );
      },
    ),
  );
}
