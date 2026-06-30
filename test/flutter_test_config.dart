import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Auto-loaded by `flutter test` for every test in this directory tree.
///
/// Makes flutter_test's "tap() derived an Offset that would not hit test on the
/// specified widget" warning *fatal* instead of a silent stderr line. A tap
/// that misses its finder almost always means the test is exercising the wrong
/// widget (e.g. tapping a truly-disabled button instead of its
/// `DisabledTapDetector` overlay), so we want CI to fail rather than let the
/// warning scroll past unnoticed.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
