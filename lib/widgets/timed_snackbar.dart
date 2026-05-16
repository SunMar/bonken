import 'dart:async';

import 'package:flutter/material.dart';

/// Pending force-close timer from the most recent [showTimedSnackBar]
/// call. Cancelled before scheduling a new one so back-to-back calls
/// don't leave a stale timer that later tries to close a snackbar that
/// has already been replaced (which trips an assertion inside
/// [ScaffoldMessengerState]).
Timer? _pendingCloseTimer;

/// Shows [snackBar] via [messenger] and force-closes it after
/// `snackBar.duration` elapses.
///
/// Wraps the standard [ScaffoldMessengerState.showSnackBar] with a
/// belt-and-suspenders [Timer]: SnackBar's built-in auto-dismiss timer
/// is unreliable on some platforms (notably web) when
/// [SnackBar.showCloseIcon] is set, so a manual close ensures the bar
/// always disappears on schedule.
///
/// Also hides any currently-visible snackbar first so back-to-back calls
/// don't queue up behind each other.
void showTimedSnackBar(ScaffoldMessengerState messenger, SnackBar snackBar) {
  _pendingCloseTimer?.cancel();
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(snackBar);
  _pendingCloseTimer = Timer(snackBar.duration, () {
    _pendingCloseTimer = null;
    controller.close();
  });
}
