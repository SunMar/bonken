import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Controls the device screen brightness while the QR-display screen is shown,
/// so a rendered QR code scans easily. Backed by a small self-written platform
/// [MethodChannel] (no third-party dependency); a no-op on web and any platform
/// without a native handler.
abstract interface class ScreenBrightness {
  /// Raise the screen to maximum brightness.
  Future<void> setMax();

  /// Restore the brightness that was in effect before [setMax].
  Future<void> reset();
}

/// Real implementation talking to the native `<appId>/brightness` channel.
///
/// The channel name is derived from the platform application id at runtime
/// (never a hardcoded literal): `package_info_plus` reports the same
/// `packageName` the native side reads (`applicationContext.packageName` /
/// `Bundle.main.bundleIdentifier`), so the two ends agree for both the current
/// (`org.suninet.bonken`) and legacy (`com.suninet.bonken`) application ids —
/// a hardcoded id would silently mismatch the legacy install and no-op.
class PlatformScreenBrightness implements ScreenBrightness {
  MethodChannel? _channel;

  Future<MethodChannel?> _resolveChannel() async {
    if (kIsWeb) return null;
    final existing = _channel;
    if (existing != null) return existing;
    final info = await PackageInfo.fromPlatform();
    return _channel = MethodChannel('${info.packageName}/brightness');
  }

  Future<void> _invoke(String method) async {
    final channel = await _resolveChannel();
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native handler (unsupported platform) — brightness is a best-effort
      // nicety, so silently no-op.
    } on PlatformException {
      // Native call failed — never let a brightness tweak break the screen.
    }
  }

  @override
  Future<void> setMax() => _invoke('setMax');

  @override
  Future<void> reset() => _invoke('reset');
}
