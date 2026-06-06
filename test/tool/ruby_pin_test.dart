// Tests for tool/helpers/ruby_pin.dart.
// No network or file I/O — pure string logic only.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/ruby_pin.dart';

void main() {
  group('parseRubyVersionPin', () {
    test('reads version from single-quoted pin', () {
      expect(parseRubyVersionPin("ruby-version: '4.0'"), (4, 0));
    });

    test('reads version from double-quoted pin', () {
      expect(parseRubyVersionPin('ruby-version: "4.0"'), (4, 0));
    });

    test('reads version from unquoted pin', () {
      expect(parseRubyVersionPin('ruby-version: 3.3'), (3, 3));
    });

    test('ignores surrounding YAML content', () {
      const yaml = '''
- name: Setup Ruby (fastlane)
  uses: ruby/setup-ruby@v1
  with:
    ruby-version: '4.0'
    working-directory: android
    bundler-cache: true
''';
      expect(parseRubyVersionPin(yaml), (4, 0));
    });

    test('returns null when no ruby-version key exists', () {
      expect(parseRubyVersionPin('bundler-cache: true'), isNull);
    });

    test('returns null for an empty string', () {
      expect(parseRubyVersionPin(''), isNull);
    });
  });

  group('parseLatestRubyBuilderCycle', () {
    test('returns the highest stable major.minor cycle', () {
      const json =
          '{"ruby": ['
          '"3.3.11", "3.4.9",'
          '"4.0.0", "4.0.5",'
          '"3.5.0-preview1", "4.0.0-preview2",'
          '"head", "debug", "asan"'
          '], "jruby": ["10.0.0.0"]}';
      expect(parseLatestRubyBuilderCycle(json), (4, 0));
    });

    test('skips preview and rc entries', () {
      const json =
          '{"ruby": ['
          '"3.4.9", "3.5.0-preview1", "4.0.0-rc1"'
          ']}';
      expect(parseLatestRubyBuilderCycle(json), (3, 4));
    });

    test('skips named builds (head, debug, asan)', () {
      const json =
          '{"ruby": ["3.3.11", "head", "debug", "asan", "asan-release"]}';
      expect(parseLatestRubyBuilderCycle(json), (3, 3));
    });

    test('returns null for invalid JSON', () {
      expect(parseLatestRubyBuilderCycle('not json'), isNull);
    });

    test('returns null when ruby key is absent', () {
      expect(parseLatestRubyBuilderCycle('{"jruby": ["10.0.0.0"]}'), isNull);
    });

    test('returns null for empty ruby list', () {
      expect(parseLatestRubyBuilderCycle('{"ruby": []}'), isNull);
    });
  });

  group('rubyIsNewer', () {
    test('higher major is newer', () {
      expect(rubyIsNewer((4, 0), (3, 3)), isTrue);
    });

    test('higher minor is newer', () {
      expect(rubyIsNewer((3, 4), (3, 3)), isTrue);
    });

    test('same version is not newer', () {
      expect(rubyIsNewer((4, 0), (4, 0)), isFalse);
    });

    test('lower version is not newer', () {
      expect(rubyIsNewer((3, 3), (4, 0)), isFalse);
    });
  });
}
