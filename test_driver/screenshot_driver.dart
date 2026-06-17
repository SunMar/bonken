import 'package:integration_test/integration_test_driver.dart';

// Screenshots are captured on the host side by generate_screenshots.sh via
// `adb exec-out screencap -p` (Android) or `xcrun simctl io … screenshot`
// (iOS), triggered by SCREENSHOT:name markers printed by the test.
// This driver just launches the integration test; no screenshot data is
// collected here.
Future<void> main() => integrationDriver();
