import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_session.dart';
import '../state/game_history_provider.dart';
import 'timed_snackbar.dart';

/// Shows the "Spel verwijderd" snackbar with an "Ongedaan maken" action that
/// re-saves the deleted [session] into the history.
///
/// Used from both the HomeScreen card trash icon and the GameScreen
/// menu so the undo affordance is consistent across delete entry points.
///
/// Capture the [ScaffoldMessengerState] *before* any awaited delete call so
/// callers don't depend on a context that may be unmounted by the time the
/// future resolves (especially when the calculator screen pops to the home
/// screen right after deleting). The undo action resolves the
/// [gameHistoryProvider] notifier through the root [ProviderContainer]
/// (looked up via [ProviderScope.containerOf]) — using the originating
/// widget's [WidgetRef] would throw or no-op once that widget has been
/// disposed by the navigation that follows the delete.
void showGameDeletedSnackBar(
  ScaffoldMessengerState messenger,
  ProviderContainer container,
  GameSession session,
) {
  showTimedSnackBar(
    messenger,
    SnackBar(
      content: const Text('Spel verwijderd'),
      duration: const Duration(seconds: 5),
      // Floating: detached pill with side margins instead of a
      // full-width bar flush to the bottom edge.
      behavior: SnackBarBehavior.floating,
      // Built-in M3 dismiss affordance: a small ✕ next to the action
      // button so users can get rid of the snackbar without waiting for
      // the auto-dismiss timer.
      showCloseIcon: true,
      action: SnackBarAction(
        label: 'Ongedaan maken',
        onPressed: () {
          container.read(gameHistoryProvider.notifier).saveGame(session);
        },
      ),
    ),
  );
}
