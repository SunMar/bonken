import 'package:flutter/material.dart';

/// Wraps [child] in a [Stack] with a transparent [GestureDetector] overlay
/// that fires [onTap] when the widget is tapped.
///
/// Intended for use with truly-disabled buttons (`onPressed: null`): the
/// overlay catches taps that the disabled button would swallow and lets callers
/// show feedback — typically a snackbar explaining what's still missing.
///
/// The overlay is wrapped in [ExcludeSemantics] so screen readers interact with
/// the underlying disabled button (WCAG-exempt native M3 disabled colours)
/// rather than an anonymous tap target.
///
/// Pass [enabled] = false to remove the overlay entirely (e.g. when the
/// button is active and handles its own taps).
class DisabledTapDetector extends StatelessWidget {
  const DisabledTapDetector({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
            ),
          ),
        ),
      ],
    );
  }
}
