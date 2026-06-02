import 'dart:async';

import 'package:flutter/material.dart';

/// Project-standard wrapper around [showModalBottomSheet] that automatically
/// accounts for the system navigation bar height.
///
/// The app runs in [SystemUiMode.edgeToEdge], so modal bottom sheets extend
/// behind the system navigation bar. [MediaQuery.padding.bottom] is consumed
/// by the Scaffold before the sheet is built, so a [SafeArea] inside the sheet
/// sees a bottom inset of 0. This wrapper injects the real physical inset via
/// [MediaQuery.viewPaddingOf] as bottom padding around the sheet content,
/// ensuring interactive content is never obscured.
///
/// Fixed defaults:
///  - `isScrollControlled: true` — lets the sheet grow to full height (so
///    [Flexible] children inside work correctly instead of being unconstrained).
///  - `useSafeArea: true` — protects the top edge (status bar / notch) when
///    the sheet expands to near full-screen height on tall content.
///
/// **Always prefer [showAppBottomSheet] over [showModalBottomSheet]** so
/// navigation-bar clearance is handled consistently.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: showDragHandle,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(sheetContext).bottom,
      ),
      child: builder(sheetContext),
    ),
  );
}
