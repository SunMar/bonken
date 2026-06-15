import 'package:bonken/screens/export_screen.dart';
import 'package:bonken/services/share_service.dart';
import 'package:bonken/state/platform_io_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test_helpers.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: ExportScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpPrefs();
  initializeWidgets();

  testWidgets('renders title "Exporteer gegevens"', (tester) async {
    await _pump(tester);
    expect(find.text('Exporteer gegevens'), findsOneWidget);
  });

  testWidgets('renders three radio options', (tester) async {
    await _pump(tester);
    expect(find.text('Alles'), findsOneWidget);
    expect(find.text('Alleen speelgeschiedenis'), findsOneWidget);
    expect(find.text('Alleen instellingen'), findsOneWidget);
  });

  testWidgets('"Alles" is selected by default', (tester) async {
    await _pump(tester);
    // The subtitle of the "Alles" tile is only shown for that option.
    expect(find.text('Speelgeschiedenis en instellingen'), findsOneWidget);
  });

  testWidgets('"Exporteer" button is enabled initially', (tester) async {
    await _pump(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Exporteer'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('share unavailable → failure snackbar, stays on screen', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'bonken',
      packageName: 'org.example.bonken',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareFileProvider.overrideWithValue(
            ({
              required bytes,
              required filename,
              required mimeType,
              subject,
              text,
            }) async => false,
          ),
        ],
        child: const MaterialApp(home: ExportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Games-only avoids needing a settings blob in prefs.
    await tester.tap(find.text('Alleen speelgeschiedenis'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Exporteer'));
    await tester.pumpAndSettle();

    expect(find.text(kShareUnsupportedMessage), findsOneWidget);
    expect(find.byType(ExportScreen), findsOneWidget); // did not pop

    await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
  });

  testWidgets('export throws → error snackbar, stays on screen', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'bonken',
      packageName: 'org.example.bonken',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareFileProvider.overrideWithValue(
            ({
              required bytes,
              required filename,
              required mimeType,
              subject,
              text,
            }) async => throw Exception('share boom'),
          ),
        ],
        child: const MaterialApp(home: ExportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Games-only avoids needing a settings blob in prefs.
    await tester.tap(find.text('Alleen speelgeschiedenis'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Exporteer'));
    await tester.pumpAndSettle();

    expect(
      find.text('Het is mislukt om de gegevens te exporteren.'),
      findsOneWidget,
    );
    expect(find.byType(ExportScreen), findsOneWidget); // did not pop

    await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
  });
}
