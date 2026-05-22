// Tests for the shared AppBar widgets used on the home + game screens:
// the Spelregels icon (now placed next to each screen's title) and the
// shared Thema menu. Pumped in isolation (no surrounding screen) so we
// cover the widgets themselves rather than each consumer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:bonken/screens/rules_screen.dart';
import 'package:bonken/state/theme_mode_provider.dart';
import 'package:bonken/widgets/app_bar_widgets.dart';

import '../test_helpers.dart';

Future<ProviderContainer> _pumpActions(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [Text('T'), RulesIconButton()],
            ),
            actions: const [ThemeMenuButton()],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openThemeMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Thema'));
  await tester.pumpAndSettle();
}

void main() {
  setUpPrefs();

  testWidgets('Spelregels icon (in title) + Thema icon (in actions) render', (
    tester,
  ) async {
    await _pumpActions(tester);
    expect(find.byTooltip('Spelregels'), findsOneWidget);
    expect(find.byTooltip('Thema'), findsOneWidget);
  });

  testWidgets('tapping Spelregels pushes the RulesScreen', (tester) async {
    await _pumpActions(tester);
    expect(find.byType(RulesScreen), findsNothing);
    await tester.tap(find.byTooltip('Spelregels'));
    await tester.pumpAndSettle();
    expect(find.byType(RulesScreen), findsOneWidget);
  });

  testWidgets('Thema menu lists the three modes', (tester) async {
    await _pumpActions(tester);
    await _openThemeMenu(tester);
    expect(find.text('Systeem'), findsOneWidget);
    expect(find.text('Licht'), findsOneWidget);
    expect(find.text('Donker'), findsOneWidget);
  });

  testWidgets('the active mode shows a trailing checkmark; others do not', (
    tester,
  ) async {
    final container = await _pumpActions(tester);
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    await tester.pump();

    await _openThemeMenu(tester);

    final donkerRow = find.ancestor(
      of: find.text('Donker'),
      matching: find.byType(MenuItemButton),
    );
    expect(
      find.descendant(of: donkerRow, matching: find.byIcon(Symbols.check)),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.check), findsOneWidget);
  });

  testWidgets('selecting a Thema entry calls setMode on the provider', (
    tester,
  ) async {
    final container = await _pumpActions(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await _openThemeMenu(tester);
    await tester.tap(find.text('Licht'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
