import 'package:flutter/material.dart';

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
  const AppScaffold({super.key, this.appBar, required this.body});

  final PreferredSizeWidget? appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(top: appBar == null, child: body),
    );
  }
}
