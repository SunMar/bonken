// Architectural guards:
//
// 1. Every screen MUST use [AppScaffold] (which wraps the body in a SafeArea
//    so content never draws under the system navigation bar) rather than the
//    raw Material [Scaffold].
//
// 2. Every modal bottom sheet MUST use [showAppBottomSheet] (which adds the
//    system navigation bar inset as bottom padding) rather than the raw
//    [showModalBottomSheet].
//
// The app runs in [SystemUiMode.edgeToEdge], so unguarded surfaces draw
// behind system bars.  See lib/widgets/app_scaffold.dart and
// lib/widgets/app_bottom_sheet.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

  test(
    'all bottom sheets use showAppBottomSheet instead of showModalBottomSheet',
    () {
      const allowList = <String>{
        'lib/widgets/app_bottom_sheet.dart', // the wrapper itself
      };

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib not found');

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (allowList.contains(entity.path)) continue;
        final source = entity.readAsStringSync();
        if (source.contains('showModalBottomSheet')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These files call showModalBottomSheet instead of '
            'showAppBottomSheet:\n'
            '  ${offenders.join('\n  ')}\n'
            'Use showAppBottomSheet from lib/widgets/app_bottom_sheet.dart\n'
            'so the system navigation bar inset is handled consistently.',
      );
    },
  );
}
