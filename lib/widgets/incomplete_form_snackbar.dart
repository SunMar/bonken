import 'package:flutter/material.dart';

import 'timed_snackbar.dart';

/// Shows a snackbar explaining why a primary form action (Opslaan /
/// save / start) could not be carried out yet because the input is
/// incomplete or invalid.  Used by screens that keep their save button
/// enabled so the user can tap it and learn *why* nothing happened —
/// instead of leaving the button silently disabled with no feedback.
///
/// Styled to match [showGameDeletedSnackBar]: floating pill with a
/// built-in close affordance. No action button — there's nothing to undo
/// and an "OK"-style button would just be visual noise.
void showIncompleteFormSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
}) {
  showTimedSnackBar(
    messenger,
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
  );
}
