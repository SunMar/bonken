import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../state/save_health_provider.dart';
import '../state/settings_provider.dart';

/// Syncs persistence to the app lifecycle on both edges:
///
///  - **Leaving the foreground** (`onHide`): flush any pending debounced game
///    autosave immediately, so an OS kill while backgrounded can't drop edits
///    still inside the 400ms debounce window (the write itself is atomic, so the
///    worst case is losing only that one in-flight write, never prior state).
///  - **Returning** (`onResume`): if a write previously failed (typically a full
///    disk), the user has most likely just freed space, so re-flush the
///    in-memory state — a recovered disk clears the save-error banner with no
///    polling. No-op while healthy.
class PersistenceLifecycleSync extends ConsumerStatefulWidget {
  const PersistenceLifecycleSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PersistenceLifecycleSync> createState() =>
      _PersistenceLifecycleSyncState();
}

class _PersistenceLifecycleSyncState
    extends ConsumerState<PersistenceLifecycleSync> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onHide: _flushPending,
      onResume: _retryIfUnhealthy,
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  // No-op when no game is active (nothing pending); settings writes are
  // immediate, so only the debounced game autosave needs flushing here.
  void _flushPending() =>
      ref.read(calculatorProvider.notifier).flushPendingAutosave();

  void _retryIfUnhealthy() {
    if (ref.read(saveHealthyProvider)) return;
    unawaited(_retry());
  }

  Future<void> _retry() async {
    await ref.read(gameHistoryProvider.notifier).retryPersist();
    await ref.read(settingsProvider.notifier).retryPersist();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
