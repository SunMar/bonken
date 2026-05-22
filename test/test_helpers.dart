import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Call at the top of a test group to reset [SharedPreferences] to empty
/// before each test.
void setUpPrefs() => setUp(() => SharedPreferences.setMockInitialValues({}));

/// Call at the top of a test group to ensure the Flutter widget bindings are
/// initialized before any test runs.
void initializeWidgets() => setUpAll(WidgetsFlutterBinding.ensureInitialized);
