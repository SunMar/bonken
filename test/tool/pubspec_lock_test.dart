// Tests for tool/helpers/pubspec_lock.dart.
// No file I/O — uses the fixture at test/tool/fixtures/pubspec_lock.txt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/pubspec_lock.dart';
import '../../tool/helpers/pubspec_yaml.dart';

void main() {
  late String lockFixture;
  late String pubspecFixture;

  setUpAll(() {
    lockFixture = File(
      'test/tool/fixtures/pubspec_lock.txt',
    ).readAsStringSync();
    pubspecFixture = File('test/tool/fixtures/pubspec.txt').readAsStringSync();
  });

  group('parseLockfileVersions', () {
    test('parses all hosted packages', () {
      final versions = parseLockfileVersions(lockFixture);
      expect(versions['flutter_riverpod'], '3.4.0');
      expect(versions['google_fonts'], '8.1.0');
      expect(versions['some_package'], '1.5.2');
      expect(versions['flutter_lints'], '6.2.0');
      expect(versions['flutter_launcher_icons'], '0.14.4');
    });

    test('excludes sdk pseudo-packages without a version field', () {
      // The sdks section has no package-style version; parseLockfileVersions
      // should not include 'dart' or 'flutter' keys.
      final versions = parseLockfileVersions(lockFixture);
      expect(versions.containsKey('dart'), isFalse);
      expect(versions.containsKey('flutter'), isFalse);
    });

    test('returns empty map for empty YAML', () {
      expect(parseLockfileVersions('packages:\n'), isEmpty);
    });
  });

  group('caret-align integration (lock → pubspec update)', () {
    test('updates caret constraints to resolved versions', () {
      final versions = parseLockfileVersions(lockFixture);
      var content = pubspecFixture;
      for (final entry in versions.entries) {
        for (final section in ['dependencies', 'dev_dependencies']) {
          final current = readYamlString(content, [section, entry.key]);
          if (current == null || !current.startsWith('^')) continue;
          content = setYamlValue(content, [
            section,
            entry.key,
          ], '^${entry.value}');
        }
      }
      // Caret deps bumped.
      expect(
        readYamlString(content, ['dependencies', 'flutter_riverpod']),
        '^3.4.0',
      );
      expect(
        readYamlString(content, ['dev_dependencies', 'flutter_lints']),
        '^6.2.0',
      );
      // Intentional non-caret pin must be untouched.
      expect(
        readYamlString(content, ['dependencies', 'google_fonts']),
        '8.1.0',
      );
    });

    // Regression: the bash predecessor used column-1 anchored grep which could
    // match flutter_launcher_icons config keys. Key-path edits can never hit
    // config sections outside dependencies/dev_dependencies.
    test(
      'key-path update cannot hit flutter_launcher_icons config section',
      () {
        const badPubspec = '''
name: test
dependencies:
  flutter_launcher_icons: ^0.14.4
flutter_launcher_icons:
  android: true
  ios: false
''';
        final updated = setYamlValue(badPubspec, [
          'dependencies',
          'flutter_launcher_icons',
        ], '^0.15.0');
        // The dependency is updated.
        expect(
          readYamlString(updated, ['dependencies', 'flutter_launcher_icons']),
          '^0.15.0',
        );
        // The config section is untouched.
        expect(
          readYamlString(updated, ['flutter_launcher_icons', 'android']),
          isNull, // boolean, not a string — so readYamlString returns null
        );
        // The raw text still shows android: true (unchanged).
        expect(updated, contains('android: true'));
      },
    );
  });
}
