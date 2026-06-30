import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether writing to local storage is currently working.
///
/// `true` (healthy) is the normal state. It flips to `false` when a persist
/// write fails — almost always because the device is out of storage space —
/// and flips back to `true` the next time any write succeeds. The UI watches
/// this to show a single, sticky save-error banner (see `SaveErrorBanner` in
/// `AppScaffold`): one piece of state means ten failed autosaves still show one
/// banner, and freeing space + any successful write clears it automatically.
///
/// The in-memory app state is unaffected throughout — only the on-disk copy is
/// behind — so the app stays fully usable while unhealthy.
class SaveHealthNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// A persist write failed (an environmental fault, not a data bug).
  void markFailed() {
    if (state) state = false;
  }

  /// A persist write succeeded.
  void markOk() {
    if (!state) state = true;
  }
}

final saveHealthyProvider = NotifierProvider<SaveHealthNotifier, bool>(
  SaveHealthNotifier.new,
);
