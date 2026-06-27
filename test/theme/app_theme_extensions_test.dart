import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  group('isDark', () {
    Future<bool> resolve(WidgetTester tester, ThemeData theme) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              result = isDark(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('false under a light theme', (tester) async {
      expect(
        await resolve(tester, ThemeData(brightness: Brightness.light)),
        isFalse,
      );
    });

    testWidgets('true under a dark theme', (tester) async {
      expect(
        await resolve(tester, ThemeData(brightness: Brightness.dark)),
        isTrue,
      );
    });
  });
}
