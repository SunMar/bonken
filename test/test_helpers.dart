import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic UUID v4 values for test fixtures that need stable game IDs.
/// All satisfy the UUID v4 invariants (version nibble = 4, variant = [89ab]).
const kGameId1 = '00000000-0000-4000-8000-000000000001';
const kGameId2 = '00000000-0000-4000-8000-000000000002';
const kGameId3 = '00000000-0000-4000-8000-000000000003';

/// Call at the top of a test group to reset [SharedPreferences] to empty
/// before each test.
void setUpPrefs() => setUp(() => SharedPreferences.setMockInitialValues({}));

/// Call at the top of a test group to ensure the Flutter widget bindings are
/// initialized before any test runs.
void initializeWidgets() => setUpAll(WidgetsFlutterBinding.ensureInitialized);
