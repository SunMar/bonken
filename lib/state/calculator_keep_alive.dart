import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calculator_provider.dart';

/// Holds [calculatorProvider] (which is `autoDispose`) alive across the
/// one-frame gap between a caller mutating it (`startNewGame` / `loadSession`)
/// and `GameScreen` subscribing via `ref.watch`.
///
/// Without this, the temporary subscription created by `ref.read` closes
/// immediately, scheduling disposal (via `Future.microtask` in
/// `flutter_riverpod`'s vsync) before the first frame draws `GameScreen` — so
/// the freshly-loaded session would be torn down in between. This opens a no-op
/// keep-alive subscription on the root container and closes it after the next
/// frame, by which point `GameScreen` has mounted and taken over the
/// subscription.
///
/// The window is exactly one frame, so the caller must navigate
/// **synchronously** after this — no awaited I/O (e.g. `saveGame`) may sit
/// between this call and the navigation. A `SharedPreferences` write is a
/// platform-channel round-trip that can span multiple rendered frames on
/// mobile; if one does, the post-frame close drops the keep-alive before
/// `GameScreen` mounts, `calculatorProvider` resets to `NoSession`, and the
/// cast in `activeSessionProvider` throws (a blank grey screen). Persist in the
/// background — after navigating — instead.
///
/// The post-frame close fires regardless of whether the caller is still
/// mounted, so a caller that bailed out earlier (e.g. `if (!mounted) return;`)
/// needs no manual cleanup. This is the single owner of the dance that both the
/// home (load) and new-game (start) entry points used to hand-roll.
void holdCalculatorAcrossNavigation(BuildContext context) {
  final sub = ProviderScope.containerOf(
    context,
    listen: false,
  ).listen<CalculatorState>(calculatorProvider, (_, _) {});
  WidgetsBinding.instance.addPostFrameCallback((_) => sub.close());
}
