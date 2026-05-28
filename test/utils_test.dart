import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:bonken/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    Future<Color> resolve(
      WidgetTester tester,
      int score,
      ThemeData theme,
    ) async {
      late Color result;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              result = scoreColor(score, context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('zero falls back to onSurfaceVariant', (tester) async {
      final theme = ThemeData(
        colorSchemeSeed: Colors.indigo,
        extensions: const [ScoreColors.light],
      );
      final color = await resolve(tester, 0, theme);
      expect(color, theme.colorScheme.onSurfaceVariant);
    });

    testWidgets('positive uses ScoreColors.positive', (tester) async {
      final theme = ThemeData(extensions: const [ScoreColors.light]);
      final color = await resolve(tester, 10, theme);
      expect(color, ScoreColors.light.positive);
    });

    testWidgets('negative uses ScoreColors.negative', (tester) async {
      final theme = ThemeData(extensions: const [ScoreColors.dark]);
      final color = await resolve(tester, -10, theme);
      expect(color, ScoreColors.dark.negative);
    });

    testWidgets('falls back to brightness defaults when extension missing', (
      tester,
    ) async {
      final theme = ThemeData(brightness: Brightness.dark);
      final color = await resolve(tester, 5, theme);
      expect(color, ScoreColors.dark.positive);
    });
  });

  group('adjustIndexAfterReorder', () {
    test('target before move (lower than both old & new) is unaffected', () {
      // List: [A, B, C, D]; move C (2) -> after D (target index 3 normalised).
      // Player at index 0 (A) should stay at 0.
      expect(adjustIndexAfterReorder(2, 3, 0), 0);
    });

    test('target equals oldIndex returns the new index', () {
      expect(adjustIndexAfterReorder(1, 3, 1), 3);
      expect(adjustIndexAfterReorder(2, 0, 2), 0);
    });

    test('target after move forward shifts down by one', () {
      // Move 1 -> 3 (normalised); index 2 was after, becomes 1.
      expect(adjustIndexAfterReorder(1, 3, 2), 1);
    });

    test('target after move backward shifts up by one', () {
      // Move 3 -> 1; index 2 was before old, after new -> becomes 3.
      expect(adjustIndexAfterReorder(3, 1, 2), 3);
    });

    test('oldIndex == newIndex leaves target unchanged', () {
      // No actual movement.
      expect(adjustIndexAfterReorder(2, 2, 0), 0);
      expect(adjustIndexAfterReorder(2, 2, 1), 1);
      expect(adjustIndexAfterReorder(2, 2, 3), 3);
    });
  });
}
