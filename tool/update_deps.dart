#!/usr/bin/env -S fvm dart
// ignore_for_file: avoid_print

// Update Dart/Flutter package dependencies the way `npm update --save` does:
//   1. Run `flutter pub upgrade` (respects existing semver ranges — no major
//      version bumps).
//   2. For every direct/dev dependency in pubspec.yaml whose constraint uses
//      a caret (`^X.Y.Z`), rewrite the caret constraint to point at the
//      currently-resolved version from pubspec.lock.
//
// Constraints WITHOUT a caret (e.g. `google_fonts: 8.1.0`) are intentional
// pins and are left untouched. SDK-style entries (`sdk: flutter`) are skipped
// automatically because they are not in the resolved-version map.
//
// Usage:
//   fvm dart run tool/update_deps.dart   # or: ./tool/update_deps.dart

import 'dart:io';

import 'helpers/pubspec_lock.dart';
import 'helpers/pubspec_yaml.dart';

const _pubspec = 'pubspec.yaml';
const _lockfile = 'pubspec.lock';

Future<void> main() async {
  if (!File(_pubspec).existsSync() || !File(_lockfile).existsSync()) {
    stderr.writeln('Run from the repo root (needs $_pubspec + $_lockfile).');
    exit(1);
  }

  print('==> fvm flutter pub upgrade (within existing constraints)');
  final upgradeResult = await Process.run('fvm', ['flutter', 'pub', 'upgrade']);
  if (upgradeResult.exitCode != 0) {
    stderr.writeln(upgradeResult.stderr);
    exit(upgradeResult.exitCode);
  }

  print('==> Aligning caret constraints in $_pubspec to resolved versions');
  final resolved = parseLockfileVersions(File(_lockfile).readAsStringSync());

  var pubspecContent = File(_pubspec).readAsStringSync();
  var pubspecChanges = 0;

  for (final entry in resolved.entries) {
    final name = entry.key;
    final resolvedVersion = entry.value;
    final newConstraint = '^$resolvedVersion';

    // Check both dependency sections. Using explicit key paths guarantees we
    // never collide with similarly-named keys in other YAML sections (e.g.
    // flutter_launcher_icons config) — the bash predecessor needed column-1
    // anchoring to avoid exactly this.
    for (final section in ['dependencies', 'dev_dependencies']) {
      final current = readYamlString(pubspecContent, [section, name]);
      if (current == null) continue; // not in this section
      if (!current.startsWith('^')) continue; // intentional non-caret pin
      if (current == newConstraint) continue; // already up to date

      print('  $name: $current -> $newConstraint');
      pubspecContent = setYamlValue(pubspecContent, [
        section,
        name,
      ], newConstraint);
      pubspecChanges++;
    }
  }

  if (pubspecChanges == 0) {
    print('==> No constraint changes — $_pubspec already matches lock file.');
  } else {
    File(_pubspec).writeAsStringSync(pubspecContent);
    print(
      '==> Rewrote $pubspecChanges constraint(s). Re-resolving to confirm…',
    );
    final getResult = await Process.run('fvm', ['flutter', 'pub', 'get']);
    if (getResult.exitCode != 0) {
      stderr.writeln(getResult.stderr);
      exit(getResult.exitCode);
    }
    print('==> Done. Review with: git diff $_pubspec $_lockfile');
  }
}
