import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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
