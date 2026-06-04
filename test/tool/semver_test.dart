// Tests for tool/helpers/semver.dart.
// No network or file I/O — pure logic only.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/semver.dart';

void main() {
  group('parseSemver', () {
    test('parses three-part version', () {
      expect(parseSemver('3.44.0'), [3, 44, 0]);
    });

    test('pads short versions with zeros', () {
      expect(parseSemver('3.44'), [3, 44, 0]);
      expect(parseSemver('3'), [3, 0, 0]);
    });

    test('strips pre-release suffix', () {
      expect(parseSemver('3.44.0-beta.1'), [3, 44, 0]);
    });

    test('strips build-metadata suffix', () {
      expect(parseSemver('3.44.0+123'), [3, 44, 0]);
    });

    test('handles non-numeric parts as 0', () {
      expect(parseSemver('3.x.0'), [3, 0, 0]);
    });
  });

  group('isNewer', () {
    test('returns false when versions are equal', () {
      expect(isNewer('3.44.0', '3.44.0'), isFalse);
    });

    test('returns true when candidate has higher patch', () {
      expect(isNewer('3.44.0', '3.44.1'), isTrue);
    });

    test('returns false when candidate has lower patch', () {
      expect(isNewer('3.44.1', '3.44.0'), isFalse);
    });

    test('returns true when candidate has higher minor', () {
      expect(isNewer('3.43.9', '3.44.0'), isTrue);
    });

    test('returns true when candidate has higher major', () {
      expect(isNewer('3.44.0', '4.0.0'), isTrue);
    });

    test('returns false when candidate has lower major', () {
      expect(isNewer('4.0.0', '3.99.9'), isFalse);
    });

    test('strips pre-release before comparing', () {
      // 3.44.0-beta vs 3.44.0 — same core, not newer
      expect(isNewer('3.44.0-beta.1', '3.44.0'), isFalse);
    });
  });
}
