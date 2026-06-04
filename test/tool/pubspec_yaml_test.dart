// Tests for tool/helpers/pubspec_yaml.dart.
// No file I/O — operates on in-memory strings only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/pubspec_yaml.dart';

void main() {
  late String fixture;

  setUpAll(() {
    fixture = File('test/tool/fixtures/pubspec.txt').readAsStringSync();
  });

  group('readYamlString', () {
    test('reads a simple scalar at a key path', () {
      expect(readYamlString(fixture, ['name']), 'test_app');
    });

    test('reads a nested scalar', () {
      expect(readYamlString(fixture, ['environment', 'sdk']), '^3.12.0');
    });

    test('reads a pinned dependency', () {
      expect(
        readYamlString(fixture, ['dependencies', 'google_fonts']),
        '8.1.0',
      );
    });

    test('reads a caret dependency', () {
      expect(
        readYamlString(fixture, ['dependencies', 'flutter_riverpod']),
        '^3.3.1',
      );
    });

    test('returns null for a missing key', () {
      expect(readYamlString(fixture, ['dependencies', 'no_such_pkg']), isNull);
    });

    test('returns null for a map value (not a scalar)', () {
      expect(readYamlString(fixture, ['dependencies']), isNull);
    });
  });

  group('setYamlValue', () {
    test('updates a nested scalar and preserves surrounding text', () {
      final updated = setYamlValue(fixture, ['environment', 'sdk'], '^3.99.0');
      expect(readYamlString(updated, ['environment', 'sdk']), '^3.99.0');
      // Comment on neighbouring line must still be present.
      expect(updated, contains('# State management'));
    });

    test(
      'editing environment.sdk leaves dependency-level sdk: flutter intact',
      () {
        final updated = setYamlValue(fixture, [
          'environment',
          'sdk',
        ], '^3.99.0');
        // The flutter SDK pseudo-dep must not be touched.
        expect(updated, contains('sdk: flutter'));
        // The environment entry must be updated.
        expect(readYamlString(updated, ['environment', 'sdk']), '^3.99.0');
      },
    );

    test('updates a dependency constraint', () {
      final updated = setYamlValue(fixture, [
        'dependencies',
        'flutter_riverpod',
      ], '^3.4.0');
      expect(
        readYamlString(updated, ['dependencies', 'flutter_riverpod']),
        '^3.4.0',
      );
      // Other dependencies must be unchanged.
      expect(
        readYamlString(updated, ['dependencies', 'google_fonts']),
        '8.1.0',
      );
    });

    test('round-trip preserves comments and formatting', () {
      final updated = setYamlValue(fixture, [
        'dependencies',
        'some_package',
      ], '^2.0.0');
      expect(updated, contains('# State management'));
      expect(updated, contains('# Intentional pin — no caret'));
      expect(updated, contains('# Font assets — version dir is updated by'));
    });
  });

  group('replaceYamlListEntry', () {
    test('replaces a matching list entry', () {
      final updated = replaceYamlListEntry(
        fixture,
        ['flutter', 'assets'],
        (e) => e.startsWith('assets/google_fonts/'),
        'assets/google_fonts/9.0.0/',
      );
      expect(updated, contains('assets/google_fonts/9.0.0/'));
      expect(updated, isNot(contains('assets/google_fonts/8.1.0/')));
    });

    test('preserves inline comment on the assets section', () {
      final updated = replaceYamlListEntry(
        fixture,
        ['flutter', 'assets'],
        (e) => e.startsWith('assets/google_fonts/'),
        'assets/google_fonts/9.0.0/',
      );
      expect(updated, contains('# Font assets — version dir is updated by'));
    });

    test('leaves unmatched entries untouched', () {
      final updated = replaceYamlListEntry(
        fixture,
        ['flutter', 'assets'],
        (e) => e.startsWith('assets/google_fonts/'),
        'assets/google_fonts/9.0.0/',
      );
      expect(updated, contains('assets/icon/icon.png'));
      expect(updated, contains('LICENSE'));
    });

    test('returns original string when no entry matches', () {
      final updated = replaceYamlListEntry(
        fixture,
        ['flutter', 'assets'],
        (e) => e.startsWith('no_match'),
        'replacement',
      );
      expect(updated, equals(fixture));
    });
  });
}
