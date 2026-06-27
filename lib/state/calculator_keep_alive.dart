import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calculator_provider.dart';

/// Holds [calculatorProvider] (which is `autoDispose`) alive across the gap
/// between a caller mutating it (`startNewGame` / `loadSession`) and
/// `GameScreen` subscribing via `ref.watch`.
///
/// Without this, the temporary subscription created by `ref.read` closes
/// immediately, scheduling disposal (via `Future.microtask` in
/// `flutter_riverpod`'s vsync) before the first frame draws `GameScreen` — so
/// the freshly-loaded session would be torn down in between. This opens a no-op
/// keep-alive subscription on the root container and closes it after the next
/// frame, by which point `GameScreen` has mounted and taken over the
/// subscription. It survives an intervening `await` (e.g. `saveGame`), since
/// that resolves on the microtask queue, before the next frame.
///
/// Call this immediately before mutating the notifier and navigating. The
/// post-frame close fires regardless of whether the caller is still mounted, so
/// a caller that bails out after an `await` (e.g. `if (!mounted) return;`)
/// needs no manual cleanup. This is the single owner of the dance that both the
/// home (load) and new-game (start) entry points used to hand-roll.
void holdCalculatorAcrossNavigation(BuildContext context) {
  final sub = ProviderScope.containerOf(
    context,
    listen: false,
  ).listen<CalculatorState>(calculatorProvider, (_, _) {});
  WidgetsBinding.instance.addPostFrameCallback((_) => sub.close());
}
