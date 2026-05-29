// Smoke tests for the About dialog opened from the home-screen AppBar's
// leading info button ([AboutIconButton]). Uses Flutter's stock
// [showAboutDialog], so we look up the localized footer-button labels
// via [MaterialLocalizations] rather than hard-coding strings.

import 'package:bonken/widgets/app_bar_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

Future<void> _pumpAboutButton(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: AboutIconButton())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAboutDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Over Bonken'));
  await tester.pumpAndSettle();
}

MaterialLocalizations _loc(WidgetTester tester) =>
    MaterialLocalizations.of(tester.element(find.byType(AboutDialog)));

void main() {
  setUpPrefs();

  testWidgets(
    'AboutIconButton opens AboutDialog with version, repo URL and icon',
    (tester) async {
      await _pumpAboutButton(tester);
      await _openAboutDialog(tester);

      expect(find.byType(AboutDialog), findsOneWidget);
      // Header shows the application name + the dev-mode version line.
      // (`flutter test` runs in debug, GIT_COMMIT is unset, so
      // resolveAboutVersionLine() takes the kDebugMode branch.)
      expect(find.text('Bonken'), findsWidgets);
      expect(find.text('Ontwikkelversie'), findsOneWidget);
      // Icon (Image.asset) is present in the dialog header.
      expect(find.byType(Image), findsOneWidget);
      // Custom children: repo and privacy links.
      expect(find.text('Broncode'), findsOneWidget);
      expect(find.text('Privacybeleid'), findsOneWidget);

      // Localized footer buttons.
      final loc = _loc(tester);
      expect(find.text(loc.viewLicensesButtonLabel), findsOneWidget);
      expect(find.text(loc.closeButtonLabel), findsOneWidget);
    },
  );

  testWidgets('Close button dismisses the AboutDialog', (tester) async {
    await _pumpAboutButton(tester);
    await _openAboutDialog(tester);
    expect(find.byType(AboutDialog), findsOneWidget);

    final closeLabel = _loc(tester).closeButtonLabel;
    await tester.tap(find.text(closeLabel));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsNothing);
  });

  testWidgets('View-licenses button pushes LicensePage', (tester) async {
    await _pumpAboutButton(tester);
    await _openAboutDialog(tester);

    final viewLicensesLabel = _loc(tester).viewLicensesButtonLabel;
    await tester.tap(find.text(viewLicensesLabel));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });

  test(
    'resolveAboutVersionLine returns dev placeholder in debug mode',
    () async {
      // `flutter test` runs in debug, and GIT_COMMIT is unset, so the
      // function takes the kDebugMode branch.
      expect(await resolveAboutVersionLine(), 'Ontwikkelversie');
    },
  );
}
