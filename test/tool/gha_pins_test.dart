// Tests for tool/helpers/gha_pins.dart.
// No network or file I/O — pure string logic only.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/gha_pins.dart';

void main() {
  group('parseActionPins', () {
    test('parses a plain action pin (repo == path)', () {
      expect(parseActionPins('    uses: actions/checkout@v6\n'), [
        (repo: 'actions/checkout', path: 'actions/checkout', ref: 'v6'),
      ]);
    });

    test(
      'parses a subdirectory action (OSV): repo vs full path + version ref',
      () {
        const yaml =
            '      uses: google/osv-scanner-action/osv-scanner-action@v2.3.8\n';
        expect(parseActionPins(yaml), [
          (
            repo: 'google/osv-scanner-action',
            path: 'google/osv-scanner-action/osv-scanner-action',
            ref: 'v2.3.8',
          ),
        ]);
      },
    );

    test('parses list-item (`- uses:`) form and varying indentation', () {
      const yaml = '''
jobs:
  build:
    steps:
      - uses: actions/checkout@v6
      -   uses:   ruby/setup-ruby@v1
''';
      expect(parseActionPins(yaml), [
        (repo: 'actions/checkout', path: 'actions/checkout', ref: 'v6'),
        (repo: 'ruby/setup-ruby', path: 'ruby/setup-ruby', ref: 'v1'),
      ]);
    });

    test('skips local ./ actions and SHA/branch pins', () {
      const yaml = '''
      - uses: ./.github/actions/setup-build
      - uses: actions/checkout@a1b2c3d4
      - uses: actions/checkout@main
''';
      expect(parseActionPins(yaml), isEmpty);
    });

    test('skips commented-out uses lines', () {
      const yaml = '''
      # uses: actions/checkout@v6
      #- uses: actions/setup-node@v4
''';
      expect(parseActionPins(yaml), isEmpty);
    });

    test('handles a trailing comment after the pin', () {
      expect(parseActionPins('    uses: actions/checkout@v6 # pin\n'), [
        (repo: 'actions/checkout', path: 'actions/checkout', ref: 'v6'),
      ]);
    });
  });

  group('isMajorRef', () {
    test('true for a bare major ref', () {
      expect(isMajorRef('v6'), isTrue);
    });

    test('false for a specific version ref', () {
      expect(isMajorRef('v2.3.8'), isFalse);
      expect(isMajorRef('v2.3'), isFalse);
    });
  });

  group('highestMajorTag', () {
    test('picks the highest bare vN tag', () {
      expect(
        highestMajorTag(['refs/tags/v1', 'refs/tags/v6', 'refs/tags/v3']),
        6,
      );
    });

    test('ignores dotted and non-version tags', () {
      expect(
        highestMajorTag([
          'refs/tags/v6.1.0',
          'refs/tags/latest',
          'refs/tags/v2',
        ]),
        2,
      );
    });

    test('returns null when no bare vN tag is present', () {
      expect(highestMajorTag(['refs/tags/v6.1.0', 'refs/heads/main']), isNull);
    });

    test('returns null for an empty list', () {
      expect(highestMajorTag(const []), isNull);
    });
  });

  group('parseNextLink', () {
    test('extracts the rel="next" url from a multi-rel header', () {
      const header =
          '<https://api.github.com/x?page=2>; rel="next", '
          '<https://api.github.com/x?page=9>; rel="last"';
      expect(parseNextLink(header), 'https://api.github.com/x?page=2');
    });

    test('returns null when only prev/last rels are present', () {
      const header =
          '<https://api.github.com/x?page=1>; rel="prev", '
          '<https://api.github.com/x?page=1>; rel="first"';
      expect(parseNextLink(header), isNull);
    });

    test('returns null for a null or empty header', () {
      expect(parseNextLink(null), isNull);
      expect(parseNextLink(''), isNull);
    });
  });

  group('highestVersionTag', () {
    test(
      'picks the highest vX.Y.Z, ignoring bare-major + non-version tags',
      () {
        expect(
          highestVersionTag([
            'refs/tags/v2.3.5',
            'refs/tags/v2.3.8',
            'refs/tags/v2',
            'refs/tags/latest',
          ]),
          '2.3.8',
        );
      },
    );

    test('compares by semver, not string (2.10.0 beats 2.9.0)', () {
      expect(
        highestVersionTag(['refs/tags/v2.9.0', 'refs/tags/v2.10.0']),
        '2.10.0',
      );
    });

    test('returns null when no specific-version tag is present', () {
      expect(highestVersionTag(['refs/tags/v2', 'refs/heads/main']), isNull);
    });
  });

  group('applyPinBump', () {
    test('bumps a bare-major pin, leaving other actions untouched', () {
      const yaml = '''
      - uses: actions/checkout@v6
      - uses: ruby/setup-ruby@v1
''';
      final out = applyPinBump(yaml, 'actions/checkout', 'v9');
      expect(out, contains('actions/checkout@v9'));
      expect(out, contains('ruby/setup-ruby@v1')); // untouched
    });

    test('bumps a specific-version subdirectory pin (OSV)', () {
      const yaml =
          '      uses: google/osv-scanner-action/osv-scanner-action@v2.3.8\n';
      final out = applyPinBump(
        yaml,
        'google/osv-scanner-action/osv-scanner-action',
        'v2.4.0',
      );
      expect(
        out,
        contains('google/osv-scanner-action/osv-scanner-action@v2.4.0'),
      );
      expect(out, isNot(contains('@v2.3.8')));
    });

    test('rewrites every occurrence of the target path', () {
      const yaml = '''
      - uses: actions/upload-artifact@v7
      - uses: actions/upload-artifact@v7
''';
      final out = applyPinBump(yaml, 'actions/upload-artifact', 'v8');
      expect('@v8'.allMatches(out).length, 2);
      expect(out, isNot(contains('@v7')));
    });

    test('is a no-op when already at the target ref', () {
      const yaml = '    uses: actions/checkout@v6\n';
      expect(applyPinBump(yaml, 'actions/checkout', 'v6'), yaml);
    });
  });

  group('parseUbuntuRunners', () {
    test('parses a pinned ubuntu-N.N runner', () {
      expect(parseUbuntuRunners('    runs-on: ubuntu-24.04\n'), {(24, 4)});
    });

    test('ignores ubuntu-latest and non-Ubuntu runners', () {
      const yaml = '''
    runs-on: ubuntu-latest
    runs-on: macos-latest
''';
      expect(parseUbuntuRunners(yaml), isEmpty);
    });

    test('collects distinct versions across a file', () {
      const yaml = '''
    runs-on: ubuntu-24.04
    runs-on: ubuntu-22.04
    runs-on: ubuntu-24.04
''';
      expect(parseUbuntuRunners(yaml), {(24, 4), (22, 4)});
    });
  });

  group('highestUbuntuImage', () {
    test('picks the highest x64 image, ignoring Arm64 + other entries', () {
      const names = [
        'Ubuntu2204-Readme.md',
        'Ubuntu2204-Arm64-Readme.md',
        'Ubuntu2404-Readme.md',
        'Ubuntu2404-Arm64-Readme.md',
        'assets',
        'scripts',
      ];
      expect(highestUbuntuImage(names), (24, 4));
    });

    test('returns null when no image readme matches', () {
      expect(highestUbuntuImage(['assets', 'README.md']), isNull);
    });
  });

  group('ubuntuIsNewer', () {
    test('true for a higher major', () {
      expect(ubuntuIsNewer((26, 4), (24, 4)), isTrue);
    });

    test('true for a higher minor within the same major', () {
      expect(ubuntuIsNewer((24, 10), (24, 4)), isTrue);
    });

    test('false for equal or older versions', () {
      expect(ubuntuIsNewer((24, 4), (24, 4)), isFalse);
      expect(ubuntuIsNewer((22, 4), (24, 4)), isFalse);
    });
  });

  group('parseMacosRunners', () {
    test('parses a pinned macos-N runner', () {
      expect(parseMacosRunners('    runs-on: macos-26\n'), {26});
    });

    test('ignores macos-latest and non-macOS runners', () {
      const yaml = '''
    runs-on: macos-latest
    runs-on: ubuntu-24.04
''';
      expect(parseMacosRunners(yaml), isEmpty);
    });

    test('collects distinct versions across a file', () {
      const yaml = '''
    runs-on: macos-26
    runs-on: macos-15
    runs-on: macos-26
''';
      expect(parseMacosRunners(yaml), {26, 15});
    });
  });

  group('highestMacosImage', () {
    test('picks the highest x64 image, ignoring arm64 + other entries', () {
      const names = [
        'macos-15-Readme.md',
        'macos-15-arm64-Readme.md',
        'macos-26-Readme.md',
        'macos-26-arm64-Readme.md',
        'assets',
        'scripts',
      ];
      expect(highestMacosImage(names), 26);
    });

    test('returns null when no image readme matches', () {
      expect(highestMacosImage(['assets', 'README.md']), isNull);
    });
  });
}
