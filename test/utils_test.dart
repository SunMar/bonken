import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/utils.dart';

void main() {
  group('formatScore', () {
    test('positive score gets a leading +', () {
      expect(formatScore(80), '+80');
    });
    test('zero is shown without sign', () {
      expect(formatScore(0), '0');
    });
    test('negative score keeps the - sign', () {
      expect(formatScore(-50), '-50');
    });
  });

  group('formatDate', () {
    test('formats Monday in January 2024 with weekday/day/month/year/time', () {
      // 2024-01-01 was a Monday at 09:05.
      final s = formatDate(DateTime(2024, 1, 1, 9, 5));
      expect(s, 'ma 1 jan 2024  09:05');
    });

    test('pads single-digit hours and minutes', () {
      final s = formatDate(DateTime(2024, 12, 31, 3, 7));
      expect(s, contains('03:07'));
    });
  });

  group('scoreColor', () {
    final cs = const ColorScheme.light();
    test('positive uses successGreen', () {
      expect(scoreColor(10, cs), successGreen);
    });
    test('negative uses cs.error', () {
      expect(scoreColor(-10, cs), cs.error);
    });
    test('zero uses cs.onSurfaceVariant', () {
      expect(scoreColor(0, cs), cs.onSurfaceVariant);
    });
  });

  group('redoubleContainer / onRedoubleContainer', () {
    final cs = const ColorScheme.light();
    test('light mode uses errorContainer', () {
      expect(redoubleContainer(cs, Brightness.light), cs.errorContainer);
      expect(onRedoubleContainer(cs, Brightness.light), cs.onErrorContainer);
    });
    test('dark mode uses hand-picked muted dark red', () {
      expect(redoubleContainer(cs, Brightness.dark), const Color(0xFF7D3535));
      expect(onRedoubleContainer(cs, Brightness.dark), const Color(0xFFFFCDD2));
    });
  });
}
