// Tests for [AmberWarningBox] in isolation: covers the label-optional
// rendering and the brightness-based [WarningColors] fallback used when
// the host theme doesn't register the extension (e.g. unthemed test
// harnesses).

import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:bonken/widgets/amber_warning_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('renders body text and the warning icon', (tester) async {
    await _pump(tester, child: const AmberWarningBox(text: 'Let op'));
    expect(find.text('Let op'), findsOneWidget);
    expect(find.byIcon(Symbols.warning_amber), findsOneWidget);
  });

  testWidgets('omits the label slot when label is null', (tester) async {
    await _pump(tester, child: const AmberWarningBox(text: 'Body only'));
    // Only the body text exists.
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('renders the bold label above the body when provided', (
    tester,
  ) async {
    await _pump(
      tester,
      child: const AmberWarningBox(label: 'Heading', text: 'Body'),
    );
    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    final labelStyle = tester.widget<Text>(find.text('Heading')).style;
    expect(labelStyle?.fontWeight, FontWeight.bold);
  });

  testWidgets('falls back to the dark warning palette without the extension', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      child: const AmberWarningBox(text: 'Donker'),
    );
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Donker'), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, WarningColors.dark.background);
  });

  testWidgets('uses the registered WarningColors extension when present', (
    tester,
  ) async {
    const custom = WarningColors(
      background: Color(0xFF112233),
      border: Color(0xFF445566),
      foreground: Color(0xFF778899),
      icon: Color(0xFFAABBCC),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [custom]),
        home: const Scaffold(body: AmberWarningBox(text: 'X')),
      ),
    );
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('X'), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, custom.background);
  });
}
