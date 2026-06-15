import 'package:flutter/material.dart';

import 'disabled_tap_detector.dart';

/// Full-width [FilledButton.icon] for use as the sole action in a
/// [BottomAppBar]. Uses a 48 dp minimum height so the button looks visually
/// proportional at full screen width (wide buttons appear shorter at 40 dp).
///
/// When [onPressed] is null and [onDisabledTap] is provided, a transparent
/// [GestureDetector] overlay sits on top of the truly-disabled button
/// (native M3 disabled colours preserved) and fires [onDisabledTap] on tap,
/// so users learn *why* the action is not available yet.
class FullWidthBottomBarButton extends StatelessWidget {
  const FullWidthBottomBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onDisabledTap,
  });

  final Widget icon;
  final Widget label;
  final VoidCallback? onPressed;
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      icon: icon,
      label: label,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, 48)),
      ),
      onPressed: onPressed,
    );
    return BottomAppBar(
      child: Row(
        children: [
          Expanded(
            child: DisabledTapDetector(
              enabled: onPressed == null && onDisabledTap != null,
              onTap: onDisabledTap ?? () {},
              child: button,
            ),
          ),
        ],
      ),
    );
  }
}

/// Project-standard [Scaffold] wrapper that automatically wraps [body] in a
/// [SafeArea] so screen content never draws under the system navigation bar.
///
/// The app runs in [SystemUiMode.edgeToEdge] (see `lib/main.dart`), so the
/// screen extends behind the status bar at the top and the gesture/nav bar
/// at the bottom.  Without a SafeArea, content would be obscured by those
/// system bars.
///
/// SafeArea defaults here:
///  - `top: false` when an [appBar] is present (the AppBar already handles
///    the status-bar inset).
///  - `top: true` when there is no AppBar.
///  - `bottom: true` always (this is the key insurance against drawing
///    under the bottom navigation bar).
///
/// **Always prefer [AppScaffold] over [Scaffold] for full-screen routes** so
/// new screens get the correct insets for free.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        top: appBar == null,
        bottom: bottomBar == null,
        // Prevents taps on rendered non-interactive elements (Card, Text) from
        // producing tiny scroll deltas that activate the AppBar's M3
        // scrolled-under elevation tint. Inner interactive widgets win the
        // gesture arena first (inner-to-outer registration order); empty gaps
        // are unaffected (deferToChild — no hit claim means no arena entry).
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () {},
          child: body,
        ),
      ),
    );
  }
}
