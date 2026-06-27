import 'package:flutter/material.dart';

import 'disabled_tap_detector.dart';

/// Mechanism A (ARCHITECTURE §2 form-CTA philosophy): a primary action that
/// stays *truly disabled* (native M3 disabled colours, WCAG-exempt) when
/// [onPressed] is `null`, while a transparent [DisabledTapDetector] overlay
/// catches taps and fires [onDisabledTap] so the user learns *why* nothing
/// happened — instead of a silently-disabled button with no feedback.
///
/// [builder] receives the (possibly `null`) [onPressed] and returns the button
/// widget. Threading the single nullable [onPressed] through both the button
/// and the overlay-enable rule makes the "disabled ⟺ overlay-on" invariant
/// un-desyncable: it was previously hand-wired at every call site as two
/// predicates kept in negated lock-step (`onPressed: x ? fn : null` next to
/// `enabled: !x`), which could silently drift.
///
/// When [onDisabledTap] is `null` no overlay is mounted even while disabled
/// (e.g. a bottom-bar action that is always enabled in practice).
///
/// This is deliberately distinct from Mechanism B (the dimmed confirm-dialog
/// "force" tiles): A is a form-completeness gate (truly disabled, snackbar
/// feedback, no state change), B announces as an enabled button and mutates on
/// confirm — do not give them a shared base.
class DisabledTappableButton extends StatelessWidget {
  const DisabledTappableButton({
    super.key,
    required this.onPressed,
    required this.onDisabledTap,
    required this.builder,
  });

  /// The action when enabled; `null` renders [builder]'s button truly disabled.
  final VoidCallback? onPressed;

  /// Fired when the disabled button is tapped (the "why" feedback). When `null`,
  /// no overlay is mounted even while disabled.
  final VoidCallback? onDisabledTap;

  /// Builds the button from the (possibly `null`) [onPressed].
  final Widget Function(VoidCallback? onPressed) builder;

  @override
  Widget build(BuildContext context) {
    return DisabledTapDetector(
      enabled: onPressed == null && onDisabledTap != null,
      onTap: onDisabledTap ?? () {},
      child: builder(onPressed),
    );
  }
}
