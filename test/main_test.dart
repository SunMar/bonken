// Tests for the bootstrap routing policy in [main.dart]: which start screen
// each `isLegacyApp` value maps to (normal → HomeScreen, legacy →
// MigrationScreen, unresolved → BootErrorScreen), and the `/spelregels[/<id>]`
// deep-link grammar. These decisions live in private top-level functions in
// `main.dart`; `startScreenFor` / `routeWidgetFor` are `@visibleForTesting` so
// the policy the baseline commit just changed (legacy → MigrationScreen) is
// locked down without driving a platform initial route.

import 'package:bonken/main.dart';
import 'package:bonken/screens/boot_error_screen.dart';
import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/screens/migration_screen.dart';
import 'package:bonken/screens/rules_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUpPrefs();
  initializeWidgets();

  group('startScreenFor', () {
    test('false (normal app id) → HomeScreen', () {
      expect(startScreenFor(false), isA<HomeScreen>());
    });

    test('true (legacy app id) → MigrationScreen', () {
      expect(startScreenFor(true), isA<MigrationScreen>());
    });

    test('null (app id could not be read) → BootErrorScreen', () {
      expect(startScreenFor(null), isA<BootErrorScreen>());
    });
  });

  group('routeWidgetFor (deep-link grammar)', () {
    test('null / "/" / empty → no deep route (falls back to start screen)', () {
      expect(routeWidgetFor(null), isNull);
      expect(routeWidgetFor('/'), isNull);
      expect(routeWidgetFor(''), isNull);
    });

    test('/spelregels → full rules document', () {
      final widget = routeWidgetFor('/spelregels');
      expect(widget, isA<RulesScreen>());
      expect((widget! as RulesScreen).singleGameId, isNull);
    });

    test('/spelregels/<gameId> → single-game rules', () {
      final widget = routeWidgetFor('/spelregels/dominoes');
      expect(widget, isA<RulesScreen>());
      expect((widget! as RulesScreen).singleGameId, 'dominoes');
    });

    test('/spelregels/ with empty id → no deep route', () {
      expect(routeWidgetFor('/spelregels/'), isNull);
    });

    test('unrecognised path → no deep route', () {
      expect(routeWidgetFor('/onbekend'), isNull);
    });
  });

  group('BonkenApp initial route', () {
    Future<void> pumpApp(WidgetTester tester, {required bool? isLegacyApp}) =>
        tester.pumpWidget(
          ProviderScope(child: BonkenApp(isLegacyApp: isLegacyApp)),
        );

    testWidgets('normal app id starts on HomeScreen', (tester) async {
      await pumpApp(tester, isLegacyApp: false);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(MigrationScreen), findsNothing);
    });

    testWidgets('legacy app id starts on MigrationScreen', (tester) async {
      await pumpApp(tester, isLegacyApp: true);
      await tester.pumpAndSettle();
      expect(find.byType(MigrationScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('unresolved app id (boot failure) starts on BootErrorScreen', (
      tester,
    ) async {
      await pumpApp(tester, isLegacyApp: null);
      await tester.pumpAndSettle();
      expect(find.byType(BootErrorScreen), findsOneWidget);
      expect(find.text('Bonken kon niet starten'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(MigrationScreen), findsNothing);
    });
  });
}
