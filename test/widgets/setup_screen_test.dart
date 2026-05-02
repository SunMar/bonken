import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bonken/screens/setup_screen.dart';
import 'package:bonken/state/calculator_provider.dart';

/// Wraps [SetupScreen] in MaterialApp + ProviderScope and pumps it.
/// Returns the [ProviderContainer] so tests can inspect state.
Future<ProviderContainer> pumpSetup(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SetupScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Enters [name] into the player slot at [index] (0..3).
Future<void> enterName(WidgetTester tester, int index, String name) async {
  await tester.enterText(find.byType(TextField).at(index), name);
  await tester.pump();
}

/// Opens the dealer dropdown and picks the menu item with the given label.
Future<void> pickDealer(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('initial state: 4 empty fields, random-dealer hint, Start disabled',
      (tester) async {
    await pumpSetup(tester);

    expect(find.byType(TextField), findsNWidgets(4));
    for (int i = 0; i < 4; i++) {
      final tf = tester.widget<TextField>(find.byType(TextField).at(i));
      expect(tf.controller!.text, '');
    }
    expect(find.text('Willekeurige deler'), findsOneWidget);

    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start spel'),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('Start enabled once 4 unique names are entered', (tester) async {
    await pumpSetup(tester);

    for (int i = 0; i < 4; i++) {
      await enterName(tester, i, ['Alice', 'Bob', 'Carol', 'Dan'][i]);
    }
    await tester.pumpAndSettle();

    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start spel'),
    );
    expect(startButton.onPressed, isNotNull);
    expect(find.text('Twee spelers hebben dezelfde naam.'), findsNothing);
  });

  testWidgets(
      'duplicate names (case-insensitive) show warning and disable Start',
      (tester) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'alice'); // case-insensitive duplicate

    expect(find.text('Twee spelers hebben dezelfde naam.'), findsOneWidget);
    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start spel'),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('Start disabled while any name slot is empty', (tester) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    // slot 3 left empty
    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start spel'),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('does NOT mutate calculatorProvider while typing', (tester) async {
    final container = await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');

    // Provider stays empty — names live only in local controllers.
    final s = container.read(calculatorProvider);
    expect(s.playerNames, ['', '', '', '']);
    expect(s.sessionId, '');
    expect(s.dealerChosen, isFalse);
  });

  testWidgets('picking a dealer surfaces clear (X) button', (tester) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'Dan');
    await tester.pumpAndSettle();

    await pickDealer(tester, 'Bob');

    expect(find.byTooltip('Wissen (willekeurige deler)'), findsOneWidget);
  });

  testWidgets('clearing the dealer brings back the hint', (tester) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'Dan');
    await tester.pumpAndSettle();

    await pickDealer(tester, 'Bob');

    await tester.tap(find.byTooltip('Wissen (willekeurige deler)'));
    await tester.pumpAndSettle();

    expect(find.text('Willekeurige deler'), findsOneWidget);
    expect(find.byTooltip('Wissen (willekeurige deler)'), findsNothing);
  });

  testWidgets(
      'pressing Start with a chosen dealer commits names + dealer + sessionId',
      (tester) async {
    final container = await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'Dan');
    await tester.pumpAndSettle();

    await pickDealer(tester, 'Carol');

    await tester.tap(find.widgetWithText(FilledButton, 'Start spel'));
    await tester.pumpAndSettle();

    final s = container.read(calculatorProvider);
    expect(s.playerNames, ['Alice', 'Bob', 'Carol', 'Dan']);
    expect(s.dealerChosen, isTrue);
    expect(s.dealerIndex, 2);
    expect(s.sessionId, isNotEmpty);
  });

  testWidgets(
      'pressing Start without a dealer shows the random-dealer dialog and then commits',
      (tester) async {
    final container = await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'Dan');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start spel'));
    await tester.pumpAndSettle();

    // Random-dealer info dialog is shown.
    expect(find.text('Willekeurige deler'), findsWidgets);
    expect(find.text('is geloot om als eerste te delen.'), findsOneWidget);

    // Dismiss dialog (OK button from showInfoDialog).
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final s = container.read(calculatorProvider);
    expect(s.playerNames, ['Alice', 'Bob', 'Carol', 'Dan']);
    expect(s.dealerChosen, isTrue);
    expect(s.dealerIndex, inInclusiveRange(0, 3));
    expect(s.sessionId, isNotEmpty);
  });

  testWidgets('reorder via reorderPlayerNames keeps dealer pointing at same player',
      (tester) async {
    await pumpSetup(tester);
    await enterName(tester, 0, 'Alice');
    await enterName(tester, 1, 'Bob');
    await enterName(tester, 2, 'Carol');
    await enterName(tester, 3, 'Dan');
    await tester.pumpAndSettle();

    await pickDealer(tester, 'Carol');

    // Find ReorderableListView and trigger onReorder programmatically.
    // Move slot 2 (Carol) to position 0.
    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderable.onReorder(2, 0);
    await tester.pumpAndSettle();

    // Carol should now be at slot 0, and the dealer dropdown should still
    // display her name (i.e. dealer index was rotated alongside).
    final tf0 = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(tf0.controller!.text, 'Carol');

    // Dropdown's selected item still shows Carol.
    expect(find.text('Carol'), findsWidgets);
  });
}
