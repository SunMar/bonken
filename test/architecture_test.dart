// Architectural guards — mechanical enforcement of the conventions in
// ARCHITECTURE.md §2/§14 and AGENTS.md. Each test source-scans `lib/` for a
// forbidden pattern and fails the build (with an offenders list) if any file
// breaks the rule. New conventions of this shape belong here.
//
//  1. Every full-screen route MUST use [AppScaffold] (wraps the body in a
//     SafeArea so content never draws under the system navigation bar) rather
//     than the raw Material [Scaffold].
//  2. Every modal bottom sheet MUST use [showAppBottomSheet] (adds the system
//     navigation-bar inset as bottom padding) rather than [showModalBottomSheet].
//  3. Every snackbar MUST use [showTimedSnackBar] (enforces showCloseIcon,
//     floating behaviour, and framework auto-dismiss via `persist: false`)
//     rather than calling [showSnackBar] directly.
//  4. Icons are `Symbols.*` only — the legacy `Icons` set is never used.
//  5. The model layer stays pure: no Flutter UI imports (bar the documented
//     IconData exception) and no up-imports into state/UI layers.
//  6. The state/services layers never import the UI layer (screens/widgets/theme).
//  7. Every screen under `lib/screens` is exercised by the a11y sweep.
//  8. Imperative navigation goes through AppRoutes — no inline MaterialPageRoute
//     outside lib/navigation/app_routes.dart and main.dart.
//
// The app runs in [SystemUiMode.edgeToEdge], so unguarded surfaces draw behind
// system bars.  See lib/widgets/app_scaffold.dart and app_bottom_sheet.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// All `.dart` files under [dir] (recursive). Fails if [dir] is missing so a
/// moved directory can't silently empty a gate.
Iterable<File> _dartFiles(String dir) sync* {
  final directory = Directory(dir);
  expect(directory.existsSync(), isTrue, reason: '$dir not found');
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

/// Files under any of [dirs] (minus [allowList]) whose source matches [forbidden].
List<String> _offenders(
  List<String> dirs,
  RegExp forbidden, {
  Set<String> allowList = const {},
}) {
  final offenders = <String>[];
  for (final dir in dirs) {
    for (final file in _dartFiles(dir)) {
      if (allowList.contains(file.path)) continue;
      if (forbidden.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
  }
  return offenders;
}

void main() {
  test('all full-screen routes use AppScaffold instead of raw Scaffold', () {
    // Scan all of lib/ (not just lib/screens) so a full-screen route defined
    // elsewhere is still caught. The wrapper itself legitimately builds a raw
    // Scaffold. `(?<!App)` lets `AppScaffold(` through.
    final offenders = _offenders(
      ['lib'],
      RegExp(r'(?<!App)Scaffold\s*\('),
      allowList: {'lib/widgets/app_scaffold.dart'},
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'These files use raw Scaffold instead of AppScaffold:\n'
          '  ${offenders.join('\n  ')}\n'
          'Use AppScaffold from lib/widgets/app_scaffold.dart so the body\n'
          'is wrapped in a SafeArea and content does not draw under the\n'
          'system navigation bar.',
    );
  });

  test(
    'all bottom sheets use showAppBottomSheet instead of showModalBottomSheet',
    () {
      final offenders = _offenders(
        ['lib'],
        RegExp('showModalBottomSheet'),
        allowList: {'lib/widgets/app_bottom_sheet.dart'}, // the wrapper itself
      );
      expect(
        offenders,
        isEmpty,
        reason:
            'These files call showModalBottomSheet instead of '
            'showAppBottomSheet:\n'
            '  ${offenders.join('\n  ')}\n'
            'Use showAppBottomSheet from lib/widgets/app_bottom_sheet.dart\n'
            'so the system navigation bar inset is handled consistently.',
      );
    },
  );

  test('all snackbars use showTimedSnackBar instead of raw showSnackBar', () {
    final offenders = _offenders(
      ['lib'],
      RegExp(r'showSnackBar\('),
      allowList: {'lib/widgets/timed_snackbar.dart'}, // calls showSnackBar
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'These files call showSnackBar directly:\n'
          '  ${offenders.join('\n  ')}\n'
          'Use showTimedSnackBar from lib/widgets/timed_snackbar.dart so\n'
          'showCloseIcon and the framework auto-dismiss (persist: false) are\n'
          'always applied.',
    );
  });

  test('iconography is Symbols.* only — no legacy Icons set', () {
    // `\bIcons\.` matches the legacy class member access (`Icons.add`) but not
    // the `material_symbols_icons` package (lowercase) or `Symbols.*`.
    final offenders = _offenders(['lib'], RegExp(r'\bIcons\.'));
    expect(
      offenders,
      isEmpty,
      reason:
          'These files reference the legacy Icons set:\n'
          '  ${offenders.join('\n  ')}\n'
          'Use Symbols.* from material_symbols_icons (even framework buttons\n'
          'are remapped) — see ARCHITECTURE.md §2/§14.',
    );
  });

  test('imperative navigation goes through AppRoutes (no inline routes)', () {
    // Every imperative screen push routes through AppRoutes
    // (lib/navigation/app_routes.dart) so route construction lives in one place
    // and lib/widgets can navigate without importing lib/screens — ARCHITECTURE
    // §10. The two legitimate route-building sites are AppRoutes itself and
    // main.dart's named/deep-link factory (onGenerateRoute).
    final offenders = _offenders(
      ['lib'],
      RegExp(r'MaterialPageRoute(<[^>]*>)?\s*\('),
      allowList: {'lib/navigation/app_routes.dart', 'lib/main.dart'},
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'These files construct a MaterialPageRoute inline:\n'
          '  ${offenders.join('\n  ')}\n'
          'Route imperative pushes through AppRoutes\n'
          '(lib/navigation/app_routes.dart) instead — see ARCHITECTURE.md §10.',
    );
  });

  test('model layer stays pure (no Flutter UI, no up-imports)', () {
    // IconData/GameSymbol glyph data is the one documented Flutter exception
    // (§2): mini_game.dart imports flutter/widgets for IconData only.
    final uiImport = RegExp(
      r"import 'package:flutter/(material|widgets|cupertino)\.dart",
    );
    final upImport = RegExp(
      r"import '(\.\./|package:bonken/)"
      r'(state|screens|widgets|services|theme|navigation)/',
    );
    final offenders = <String>[];
    for (final file in _dartFiles('lib/models')) {
      final source = file.readAsStringSync();
      final leaksUi =
          uiImport.hasMatch(source) && file.path != 'lib/models/mini_game.dart';
      if (leaksUi || upImport.hasMatch(source)) offenders.add(file.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These model files break the pure-domain rule (§2 "nothing points\n'
          'back up"):\n'
          '  ${offenders.join('\n  ')}\n'
          'lib/models must not import Flutter UI (material/widgets/cupertino,\n'
          'bar the IconData exception) nor any lib/{state,screens,widgets,\n'
          'services,theme,navigation} file.',
    );
  });

  test('state and services never import the UI layer', () {
    // State MAY use Flutter (e.g. `material.dart show ThemeMode`,
    // `widgets.dart` for the keep-alive bridge) — only up-imports into the
    // UI layer are forbidden. Matches lib/{screens,widgets,theme,navigation}
    // (navigation transitively pulls in screens), not the flutter/widgets
    // package.
    final upImport = RegExp(
      r"import '(\.\./|package:bonken/)(screens|widgets|theme|navigation)/",
    );
    final offenders = _offenders(['lib/state', 'lib/services'], upImport);
    expect(
      offenders,
      isEmpty,
      reason:
          'These state/services files import the UI layer (§3 "dependencies\n'
          'point downward only"):\n'
          '  ${offenders.join('\n  ')}\n'
          'State and services must not import lib/{screens,widgets,theme,\n'
          'navigation} — a notifier reaching for a widget helper (or the\n'
          'navigation hub, which pulls in screens) is the regression this guards.',
    );
  });

  test('every screen under lib/screens is exercised by the a11y sweep', () {
    final a11ySource = File('test/a11y_test.dart').readAsStringSync();
    final offenders = <String>[];
    for (final file in _dartFiles('lib/screens')) {
      final importPath = file.path.replaceFirst('lib/', 'package:bonken/');
      if (!a11ySource.contains(importPath)) offenders.add(file.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These screens are not imported (and so not pumped) in\n'
          'test/a11y_test.dart:\n'
          '  ${offenders.join('\n  ')}\n'
          'Every top-level route must be checked against the a11y guidelines\n'
          '— add a `_pump(tester, const <Screen>())` + `_expectA11y` block.',
    );
  });
}
