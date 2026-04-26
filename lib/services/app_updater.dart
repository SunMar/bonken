import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Asks the Google Play Store whether a newer version of the app is
/// available, and — if so — kicks off a *flexible* in-app update.
///
/// "Flexible" means the new APK is downloaded in the background while the
/// user keeps using the app.  When the download finishes the user is asked
/// (by Play, via the in-app prompt) whether to install and restart.  Nothing
/// here ever blocks the UI.
///
/// The whole thing is a no-op on platforms other than Android, and silently
/// does nothing if the app was not installed via the Play Store (e.g. debug
/// builds, sideloaded APKs).
Future<void> checkForAndroidUpdate() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid) return;

  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return;
    }
    if (info.flexibleUpdateAllowed != true) return;

    // Start the background download.  The future resolves when the user
    // accepts/declines the Play prompt; we ignore the result because the
    // app keeps working either way.
    await InAppUpdate.startFlexibleUpdate();

    // Once Play reports the download is done, ask Play to install + restart.
    // If the user dismisses the snackbar this is also fine — the install
    // will happen the next time the app starts.
    await InAppUpdate.completeFlexibleUpdate();
  } catch (e) {
    // Most common reasons we get here:
    //   * App was sideloaded (not installed via Play).
    //   * Device has no Play Services / no network.
    //   * No newer versionCode published.
    // None of these should affect the running app, so swallow.
    debugPrint('In-app update check skipped: $e');
  }
}
