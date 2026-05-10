// Architectural guard: every screen MUST use [AppScaffold] (which wraps the
// body in a SafeArea so content never draws under the system navigation bar)
// rather than the raw Material [Scaffold].
//
// The app runs in [SystemUiMode.edgeToEdge], so a bare Scaffold body would
// draw under the bottom gesture/nav bar.  See lib/widgets/app_scaffold.dart.
//
// If you legitimately need a raw Scaffold (e.g. for a Material modal that
// already handles insets), add the file to the [allowList] below.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('all screens use AppScaffold instead of raw Scaffold', () {
    const allowList = <String>{
      // (none — every full-screen route should use AppScaffold)
    };

    final screensDir = Directory('lib/screens');
    expect(screensDir.existsSync(), isTrue, reason: 'lib/screens not found');

    final offenders = <String>[];
    for (final entity in screensDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (allowList.contains(entity.path)) continue;
      final source = entity.readAsStringSync();
      // Match `Scaffold(` not preceded by `App` (so AppScaffold passes).
      final regex = RegExp(r'(?<!App)Scaffold\s*\(');
      if (regex.hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These screen files use raw Scaffold instead of AppScaffold:\n'
          '  ${offenders.join('\n  ')}\n'
          'Use AppScaffold from lib/widgets/app_scaffold.dart so the body\n'
          'is wrapped in a SafeArea and content does not draw under the\n'
          'system navigation bar.',
    );
  });
}
