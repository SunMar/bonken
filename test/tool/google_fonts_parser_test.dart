// Tests for tool/helpers/google_fonts_parser.dart.
// Uses fixture snippets extracted from the real google_fonts 8.1.0 source so a
// future layout change in that package fails here at `flutter test` time rather
// than silently at the next font bump.
// No network or subprocess — pure parse logic only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/google_fonts_parser.dart';
import '../../tool/helpers/pubspec_yaml.dart';

void main() {
  late String robotoSource;
  late String arimoSource;

  setUpAll(() {
    robotoSource = File(
      'test/tool/fixtures/part_r_roboto.txt',
    ).readAsStringSync();
    arimoSource = File(
      'test/tool/fixtures/part_a_arimo.txt',
    ).readAsStringSync();
  });

  group('parseFontVariants (Roboto)', () {
    test('parses at least 9 variants (w100–w900, normal + italic)', () {
      final variants = parseFontVariants(robotoSource, 'roboto');
      expect(variants.length, greaterThanOrEqualTo(9));
    });

    test('contains w400/w500/w700 normal variants', () {
      final variants = parseFontVariants(robotoSource, 'roboto');
      for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w700]) {
        expect(
          variants.any(
            (v) => v.fontWeight == w && v.fontStyle == FontStyle.normal,
          ),
          isTrue,
          reason: 'missing $w normal',
        );
      }
    });

    test('w400 normal hash matches the known 8.1.0 value', () {
      final variants = parseFontVariants(robotoSource, 'roboto');
      expect(
        hashForWeight(variants, FontWeight.w400),
        '7f3ec5073a282c666c9a0063573345841229caf50ed34d33017e20d441bf5caf',
      );
    });

    test('w700 normal hash matches the known 8.1.0 value', () {
      final variants = parseFontVariants(robotoSource, 'roboto');
      expect(
        hashForWeight(variants, FontWeight.w700),
        'a059c7343a09d6144d964625cb5d7cd9a0692772f981920c253941600447cb8d',
      );
    });

    test('throws FormatException when font name is not found', () {
      expect(
        () => parseFontVariants(robotoSource, 'notAFont'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parseFontVariants (Arimo)', () {
    test('contains at least one variant', () {
      final variants = parseFontVariants(arimoSource, 'arimo');
      expect(variants, isNotEmpty);
    });

    test('w400 normal hash matches the known 8.1.0 value', () {
      final variants = parseFontVariants(arimoSource, 'arimo');
      expect(
        hashForWeight(variants, FontWeight.w400),
        'dbc3f5256cfcb1aa62736daaab3bea7dc85c7c68028cd408671a796537da3a0e',
      );
    });
  });

  group('asset path update via pubspec_yaml helper', () {
    const fixtureYaml = '''
flutter:
  # Font assets — version dir is updated by tool/update_fonts.dart
  assets:
    - assets/google_fonts/8.1.0/
    - assets/icon/icon.png
''';

    test('replaces google_fonts version in assets list', () {
      final updated = replaceYamlListEntry(
        fixtureYaml,
        ['flutter', 'assets'],
        (e) => e.startsWith('assets/google_fonts/'),
        'assets/google_fonts/9.0.0/',
      );
      expect(updated, contains('assets/google_fonts/9.0.0/'));
      expect(updated, isNot(contains('assets/google_fonts/8.1.0/')));
    });

    test('preserves comment on the assets section', () {
      final updated = replaceYamlListEntry(
        fixtureYaml,
        ['flutter', 'assets'],
        (e) => e.startsWith('assets/google_fonts/'),
        'assets/google_fonts/9.0.0/',
      );
      expect(updated, contains('# Font assets — version dir is updated by'));
    });
  });
}
