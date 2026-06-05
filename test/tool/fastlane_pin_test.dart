// Tests for tool/helpers/fastlane_pin.dart.
// No network or file I/O — pure string logic only.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/fastlane_pin.dart';

void main() {
  group('parseFastlanePinMajor', () {
    test('reads the major from a `~> N` constraint', () {
      expect(parseFastlanePinMajor('gem "fastlane", "~> 2"'), 2);
    });

    test('reads the major from a `~> N.M` constraint', () {
      expect(parseFastlanePinMajor('gem "fastlane", "~> 2.230"'), 2);
    });

    test('reads the major from an exact version', () {
      expect(parseFastlanePinMajor('gem "fastlane", "2.235.0"'), 2);
    });

    test('reads the major from a compound `>=, <` constraint', () {
      expect(parseFastlanePinMajor('gem "fastlane", ">= 2.0, < 3.0"'), 2);
    });

    test('accepts single quotes', () {
      expect(parseFastlanePinMajor("gem 'fastlane', '~> 2'"), 2);
    });

    test('ignores other gems and surrounding lines', () {
      const gemfile = '''
source "https://rubygems.org"

gem "cocoapods", "~> 1.15"
gem "fastlane", "~> 2"
''';
      expect(parseFastlanePinMajor(gemfile), 2);
    });

    test('returns null for a versionless fastlane pin', () {
      expect(parseFastlanePinMajor('gem "fastlane"'), isNull);
    });

    test('returns null when fastlane is absent', () {
      expect(parseFastlanePinMajor('gem "cocoapods", "~> 1.15"'), isNull);
    });
  });
}
