import 'dart:async';

import 'package:flutter/material.dart';

/// Pending force-close timer from the most recent [showTimedSnackBar] call.
/// Cancelled before scheduling a new one so back-to-back calls don't leave a
/// stale timer that later tries to close a snackbar that has already been
/// replaced (which trips an assertion inside [ScaffoldMessengerState]).
///
/// A single variable works because [showTimedSnackBar] calls
/// [ScaffoldMessengerState.hideCurrentSnackBar] before showing a new one, so
/// there is never more than one snackbar on screen at a time. The app uses a
/// single root [ScaffoldMessengerState], so this is always true. If the app
/// ever introduces a second messenger, this logic will need to be updated to
/// track a timer per messenger instance.
Timer? _pendingCloseTimer;

/// Project-standard snackbar helper.
///
/// Always sets [SnackBar.showCloseIcon] to `true` and wraps
/// [ScaffoldMessengerState.showSnackBar] with a belt-and-suspenders [Timer]:
/// SnackBar's built-in auto-dismiss timer is unreliable on some platforms
/// (notably web) when [SnackBar.showCloseIcon] is set, so a manual close
/// ensures the bar always disappears on schedule.
///
/// Also hides any currently-visible snackbar first so back-to-back calls
/// don't queue up behind each other.
///
/// Actionable snackbars (an [action] is given) stay on screen a little longer
/// (6s) so the user has time to act — Material allows up to ~10s for actionable
/// snackbars; plain ones use Flutter's 4s default.
///
/// **Always prefer [showTimedSnackBar] over calling [showSnackBar] directly**
/// so the close icon and web auto-dismiss timer are never accidentally omitted.
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
    duration: action != null
        ? const Duration(seconds: 6)
        : const Duration(seconds: 4),
  );
  _pendingCloseTimer?.cancel();
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(snackBar);
  _pendingCloseTimer = Timer(snackBar.duration, () {
    _pendingCloseTimer = null;
    controller.close();
  });
}
