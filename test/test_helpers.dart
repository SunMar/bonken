import 'package:bonken/services/screen_brightness_service.dart';
import 'package:bonken/widgets/qr_scanner_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Deterministic UUID v4 values for test fixtures that need stable game IDs.
/// All satisfy the UUID v4 invariants (version nibble = 4, variant = [89ab]).
const kGameId1 = '00000000-0000-4000-8000-000000000001';
const kGameId2 = '00000000-0000-4000-8000-000000000002';
const kGameId3 = '00000000-0000-4000-8000-000000000003';

/// Installs a fresh in-memory `SharedPreferencesAsync` backend (the API the
/// storage layer now uses), optionally seeded with [data]. Replaces the whole
/// store on each call — the async equivalent of the legacy
/// `SharedPreferences.setMockInitialValues({...})`, and a drop-in for it.
void setAsyncPrefs([Map<String, Object> data = const {}]) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(data);
}

/// Installs an async prefs backend whose **writes** throw (reads still work),
/// to exercise the persistence-write-fault paths (full disk → save-error
/// banner). Seed with [data] for the reads.
void setAsyncPrefsWithFailingWrites([Map<String, Object> data = const {}]) {
  SharedPreferencesAsyncPlatform.instance = _WriteFailingAsyncPrefs(data);
}

final class _WriteFailingAsyncPrefs extends InMemorySharedPreferencesAsync {
  _WriteFailingAsyncPrefs(super.data) : super.withData();

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async => throw Exception('simulated write fault (full disk)');
}

/// Call at the top of a test group to reset the `SharedPreferencesAsync` store
/// to [initial] (empty by default) before each test.
///
/// Note `main()`'s one-off legacy→async migration is NOT exercised here — widget
/// tests pump screens directly, so they read/write the async store seeded here.
void setUpPrefs([Map<String, Object> initial = const {}]) =>
    setUp(() => setAsyncPrefs(initial));

/// Call at the top of a test group to ensure the Flutter widget bindings are
/// initialized before any test runs.
void initializeWidgets() => setUpAll(WidgetsFlutterBinding.ensureInitialized);

/// Test double for [ScreenBrightness] (the QR-display screen's brightness seam):
/// records call counts and touches no platform.
class FakeScreenBrightness implements ScreenBrightness {
  int setMaxCount = 0;
  int resetCount = 0;

  @override
  Future<void> setMax() async => setMaxCount++;

  @override
  Future<void> reset() async => resetCount++;
}

/// Test double for the camera scanner seam ([qrScannerViewProvider]). Renders a
/// non-interactive placeholder (no real camera) and captures the screen's
/// callbacks so a test can simulate a scan via [emit] or a camera failure via
/// [fail].
class FakeScannerView {
  void Function(String raw)? _onDetect;
  VoidCallback? _onUnavailable;

  QrScannerView get builder => ({required onDetect, required onUnavailable}) {
    _onDetect = onDetect;
    _onUnavailable = onUnavailable;
    return const ColoredBox(color: Color(0xFF000000), child: SizedBox.expand());
  };

  /// Simulate scanning a code whose raw decoded value is [raw].
  void emit(String raw) => _onDetect?.call(raw);

  /// Simulate the camera being denied or unavailable.
  void fail() => _onUnavailable?.call();
}
