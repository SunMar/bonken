// Tests for [ThemeModeButton] in the home-screen AppBar: opening the
// MenuAnchor, picking a mode, and rendering the trailing checkmark on
// the active entry.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/state/theme_mode_provider.dart';

Future<ProviderContainer> _pumpButton(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: Center(child: ThemeModeButton())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping the button opens the menu with all three entries', (
    tester,
  ) async {
    await _pumpButton(tester);

    await tester.tap(find.byTooltip('Thema'));
    await tester.pumpAndSettle();

    expect(find.text('Systeem'), findsOneWidget);
    expect(find.text('Licht'), findsOneWidget);
    expect(find.text('Donker'), findsOneWidget);
  });

  testWidgets('the active mode shows a trailing checkmark; others do not', (
    tester,
  ) async {
    final container = await _pumpButton(tester);
    // Default state is ThemeMode.system; flip to dark for an unambiguous
    // assertion (system is also the default order, so a checkmark on
    // "Systeem" would coincide with the natural top entry).
    container.read(themeModeProvider.notifier).state = ThemeMode.dark;
    await tester.pump();

    await tester.tap(find.byTooltip('Thema'));
    await tester.pumpAndSettle();

    // The trailing-icon slot of MenuItemButton renders the checkmark as
    // a Symbols.check glyph; only the active row should have one.
    expect(find.byIcon(Symbols.check), findsOneWidget);
    final checkmark = tester.widget<Icon>(find.byIcon(Symbols.check));
    final donkerRow = find.ancestor(
      of: find.text('Donker'),
      matching: find.byType(MenuItemButton),
    );
    expect(
      find.descendant(of: donkerRow, matching: find.byIcon(Symbols.check)),
      findsOneWidget,
    );
    expect(checkmark.size, 16);
  });

  testWidgets('selecting a menu entry calls setMode on the provider', (
    tester,
  ) async {
    final container = await _pumpButton(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.byTooltip('Thema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licht'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  testWidgets('the IconButton glyph matches the active mode', (tester) async {
    final container = await _pumpButton(tester);

    // System -> contrast.
    expect(find.byIcon(Symbols.contrast), findsOneWidget);

    container.read(themeModeProvider.notifier).state = ThemeMode.light;
    await tester.pump();
    expect(find.byIcon(Symbols.light_mode), findsOneWidget);

    container.read(themeModeProvider.notifier).state = ThemeMode.dark;
    await tester.pump();
    expect(find.byIcon(Symbols.dark_mode), findsOneWidget);
  });
}
