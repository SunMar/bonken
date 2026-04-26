import 'package:flutter/material.dart';

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
      return AlertDialog(
        title: Text(title),
        content: content ?? Text(contentText!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  )
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
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}
