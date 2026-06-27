import 'package:flutter/material.dart';

/// Project-standard snackbar helper.
///
/// Shows [content] via [ScaffoldMessengerState.showSnackBar] with the close
/// icon always present, and lets the framework auto-dismiss the bar after its
/// [SnackBar.duration].
///
/// The one non-obvious flag is `persist: false`. Since Flutter 3.38 a SnackBar
/// *with an action* no longer auto-dismisses by default; setting it `false`
/// restores "dismiss after [SnackBar.duration]" uniformly for both the action
/// and plain paths, so the framework owns the whole lifecycle and the app keeps
/// no timer of its own (it also cancels that timer on any manual close, so a
/// dismissed bar never leaves a pending timer behind).
///
/// Also hides any currently-visible snackbar first so back-to-back calls don't
/// queue up behind each other.
///
/// Actionable snackbars (an [action] is given) stay on screen a little longer
/// (6s) so the user has time to act — Material allows up to ~10s for actionable
/// snackbars; plain ones use Flutter's 4s default.
///
/// **Always prefer [showTimedSnackBar] over calling [showSnackBar] directly**
/// so the close icon and auto-dismiss are never accidentally omitted.
void showTimedSnackBar(
  ScaffoldMessengerState messenger, {
  required Widget content,
  SnackBarAction? action,
}) {
  final snackBar = SnackBar(
    content: content,
    action: action,
    behavior: SnackBarBehavior.floating,
    showCloseIcon: true,
    // Auto-dismiss after `duration` even with an action (Flutter 3.38+ makes
    // action snackbars persist by default).
    persist: false,
    duration: action != null
        ? const Duration(seconds: 6)
        : const Duration(seconds: 4),
  );
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(snackBar);
}
