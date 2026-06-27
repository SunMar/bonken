import 'dart:async';

import 'package:bonken/screens/export_screen.dart';
import 'package:bonken/services/io_failure.dart'
    show OutOfSpaceException, kOutOfSpaceMessage;
import 'package:bonken/state/platform_io_providers.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
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
    expect(find.text('Alleen spelgeschiedenis'), findsOneWidget);
    expect(find.text('Alleen instellingen'), findsOneWidget);
  });

  testWidgets('"Alles" is selected by default', (tester) async {
    await _pump(tester);
    // The subtitle of the "Alles" tile is only shown for that option.
    expect(find.text('Speelgeschiedenis en instellingen'), findsOneWidget);
  });

  testWidgets('action buttons are enabled initially', (tester) async {
    await _pump(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Export delen'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Export opslaan'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    '"Export delen" out of space → storage snackbar, stays on screen',
    (tester) async {
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
              }) async => throw const OutOfSpaceException(),
            ),
          ],
          child: const MaterialApp(home: ExportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Games-only avoids needing a settings blob in prefs.
      await tester.tap(find.text('Alleen spelgeschiedenis'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Export delen'));
      await tester.pumpAndSettle();

      expect(find.text(kOutOfSpaceMessage), findsOneWidget);
      expect(find.byType(ExportScreen), findsOneWidget); // did not pop

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    },
  );

  testWidgets('"Export delen" throws → error snackbar, stays on screen', (
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
    await tester.tap(find.text('Alleen spelgeschiedenis'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export delen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Het is mislukt om de gegevens te exporteren.'),
      findsOneWidget,
    );
    expect(find.byType(ExportScreen), findsOneWidget); // did not pop

    await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
  });

  testWidgets(
    '"Export opslaan" save cancelled → stays on screen, no snackbar',
    (tester) async {
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
            saveZipFileProvider.overrideWithValue(
              ({required bytes, required filename}) async => false,
            ),
          ],
          child: const MaterialApp(home: ExportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alleen spelgeschiedenis'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Export opslaan'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportScreen), findsOneWidget); // did not pop
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    '"Export opslaan" save throws → error snackbar, stays on screen',
    (tester) async {
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
            saveZipFileProvider.overrideWithValue(
              ({required bytes, required filename}) async =>
                  throw Exception('save boom'),
            ),
          ],
          child: const MaterialApp(home: ExportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alleen spelgeschiedenis'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Export opslaan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Het is mislukt om de gegevens op te slaan.'),
        findsOneWidget,
      );
      expect(find.byType(ExportScreen), findsOneWidget); // did not pop

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    },
  );

  testWidgets(
    '"Export opslaan" out of space → storage snackbar, stays on screen',
    (tester) async {
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
            saveZipFileProvider.overrideWithValue(
              ({required bytes, required filename}) async =>
                  throw const OutOfSpaceException(),
            ),
          ],
          child: const MaterialApp(home: ExportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alleen spelgeschiedenis'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Export opslaan'));
      await tester.pumpAndSettle();

      expect(find.text(kOutOfSpaceMessage), findsOneWidget);
      expect(find.byType(ExportScreen), findsOneWidget); // did not pop

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    },
  );

  testWidgets(
    'export in flight: action buttons + scope radio locked, spinner shown',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'bonken',
        packageName: 'org.example.bonken',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      // A gate that never completes until we say so keeps the save in flight,
      // so the busy frame is observable (the existing tests resolve instantly).
      final gate = Completer<bool>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            saveZipFileProvider.overrideWithValue(
              ({required bytes, required filename}) => gate.future,
            ),
          ],
          child: const MaterialApp(home: ExportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Games-only avoids needing a settings blob in prefs.
      await tester.tap(find.text('Alleen spelgeschiedenis'));
      await tester.pumpAndSettle();

      // Read the scope without naming the private _ExportScope generic.
      Object? scopeValue() =>
          (tester.widget(find.byWidgetPredicate((w) => w is RadioGroup))
                  as dynamic)
              .groupValue;
      final lockedScope = scopeValue();

      await tester.tap(find.widgetWithText(FilledButton, 'Export opslaan'));
      await tester.pump(); // setState(_busy = save)
      await tester.pump(); // _buildExport resolves; save provider hangs on gate

      // Both action buttons are disabled while the export is in flight…
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Export opslaan'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Export delen'),
            )
            .onPressed,
        isNull,
      );
      // …the active button shows the spinner…
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // …and the scope radio is locked: tapping another option is a no-op.
      await tester.tap(find.text('Alleen instellingen'));
      await tester.pump();
      expect(scopeValue(), lockedScope);

      // Release the export so no future dangles at teardown.
      gate.complete(false);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('"Export opslaan" success pops the screen', (tester) async {
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
          saveZipFileProvider.overrideWithValue(
            ({required bytes, required filename}) async => true,
          ),
        ],
        // ExportScreen pops on success, so push it onto a host route rather
        // than mounting it as the root (which can't be popped).
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExportScreen(),
                    ),
                  ),
                  child: const Text('open export'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open export'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportScreen), findsOneWidget);

    await tester.tap(find.text('Alleen spelgeschiedenis'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export opslaan'));
    await tester.pumpAndSettle();

    // A successful save pops the export screen back to the host route.
    expect(find.byType(ExportScreen), findsNothing);
    expect(find.text('open export'), findsOneWidget);
  });

  testWidgets('"Export opslaan" success on iOS shows the saved snackbar', (
    tester,
  ) async {
    // Reset in `finally`, not `addTearDown`: the binding asserts all debug
    // foundation vars are unset at the END of the test body, which runs before
    // teardown callbacks.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
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
            saveZipFileProvider.overrideWithValue(
              ({required bytes, required filename}) async => true,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ExportScreen(),
                      ),
                    ),
                    child: const Text('open export'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open export'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alleen spelgeschiedenis'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Export opslaan'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportScreen), findsNothing); // popped
      expect(
        find.text('Export opgeslagen in Bestanden → Bonken'),
        findsOneWidget,
      );

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
