#!/usr/bin/env -S fvm dart
// ignore_for_file: avoid_print

// Upgrade to the latest **stable**-channel Flutter SDK release, keeping the
// project's version pins in lock-step:
//   1. Fetch the official Flutter releases manifest and read the current
//      stable-channel release (its Flutter version + bundled Dart SDK version).
//   2. Compare against the pin in `.fvmrc` (the single source of truth — CI's
//      `subosito/flutter-action` installs `flutter-version-file: .fvmrc` on
//      `channel: stable`).
//   3. If a newer stable exists, rewrite `.fvmrc` to the new Flutter version and
//      bump the Dart `sdk:` lower-bound in `pubspec.yaml` to the bundled Dart
//      version (only when it's a caret constraint — explicit pins are left
//      alone, matching `tool/update_deps.dart`).
//   4. Run `fvm install` to install the pinned SDK (fast no-op if already
//      installed).
//   5. Sync Android toolchain versions (AGP, Kotlin, Gradle) from the Flutter
//      SDK's own pinned defaults (read from the installed SDK's gradle_utils.dart).
//
// Steps 4–5 only run when an update is applied. Pass --force to run them even
// when the pin is already current (e.g. to re-sync Android after a manual SDK
// change without bumping the Flutter version).
//
// Never downgrades: if the pin is already ahead of the latest stable release,
// the Flutter version is left as-is.
//
// Usage (either form works):
//   ./tool/update_flutter.dart [--check|--force]        # executable (shebang)
//   fvm dart run tool/update_flutter.dart [--check|--force]

import 'dart:convert';
import 'dart:io';

import 'helpers/android_versions.dart';
import 'helpers/flutter_release.dart';
import 'helpers/pubspec_yaml.dart';
import 'helpers/semver.dart';

const _fvmrc = '.fvmrc';
const _pubspec = 'pubspec.yaml';
const _settingsGradle = 'android/settings.gradle.kts';
const _gradleWrapper = 'android/gradle/wrapper/gradle-wrapper.properties';

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final force = args.contains('--force');
  if (checkOnly && force) {
    stderr.writeln('--check and --force are mutually exclusive.');
    exit(2);
  }
  if (args.any((a) => a != '--check' && a != '--force')) {
    stderr.writeln(
      'Usage: fvm dart run tool/update_flutter.dart [--check|--force]',
    );
    exit(2);
  }
  if (!File(_fvmrc).existsSync() ||
      !File(_pubspec).existsSync() ||
      !File(_settingsGradle).existsSync() ||
      !File(_gradleWrapper).existsSync()) {
    stderr.writeln(
      'Run from the repo root '
      '(needs $_fvmrc + $_pubspec + Android build files).',
    );
    exit(1);
  }

  final (latestFlutter, latestDart) = await _resolveTargetStable();
  final currentFlutter = _readFvmrcFlutter();
  final currentDart = _readPubspecDart();

  print('    Pinned : Flutter $currentFlutter  (Dart ${currentDart ?? '?'})');
  print('    Latest : Flutter $latestFlutter  (Dart $latestDart, stable)');

  final needsFlutterUpdate = isNewer(currentFlutter, latestFlutter);

  if (checkOnly) {
    if (needsFlutterUpdate) {
      print('==> Update available: Flutter $currentFlutter -> $latestFlutter');
      print(
        '    (--check) Not applying. Run without --check to update the pin.',
      );
      exit(1);
    }
    print('==> Already on the latest stable Flutter ($currentFlutter).');
    return;
  }

  if (!needsFlutterUpdate) {
    if (!force) {
      print(
        '==> Already on the latest stable Flutter ($currentFlutter). Nothing to do.\n'
        '    Use --force to run fvm install + Android toolchain sync anyway.',
      );
      return;
    }
    print(
      '==> Already on the latest stable Flutter ($currentFlutter) — running --force.',
    );
  }

  if (needsFlutterUpdate) {
    print('==> Update available: Flutter $currentFlutter -> $latestFlutter');
    _writeFvmrcFlutter(latestFlutter);
    print('    $_fvmrc: flutter $currentFlutter -> $latestFlutter');

    // Only update the Dart constraint when it's a caret constraint — explicit
    // pins (e.g. `sdk: 3.12.0`) are intentional and left untouched.
    if (currentDart != null && currentDart != latestDart) {
      _writePubspecDart(latestDart);
      print('    $_pubspec: sdk ^$currentDart -> ^$latestDart');
    }
  }

  // Install the pinned SDK before syncing Android versions (fast no-op when
  // already installed; guarantees the sync below reads from the correct SDK).
  print('==> Running fvm install');
  final installProcess = await Process.start('fvm', [
    'install',
  ], mode: ProcessStartMode.inheritStdio);
  if (await installProcess.exitCode != 0) {
    exit(1);
  }

  // ── Android toolchain versions ─────────────────────────────────────────────
  // AGP, Kotlin, and Gradle versions are pinned by the Flutter SDK itself.
  // Sync them from the SDK installed above.

  print('==> Syncing Android toolchain versions with Flutter SDK');
  final versionResult = await Process.run('fvm', [
    'flutter',
    '--version',
    '--machine',
  ]);
  if (versionResult.exitCode != 0) {
    stderr.writeln(versionResult.stderr);
    exit(versionResult.exitCode);
  }
  final versionJson =
      jsonDecode(versionResult.stdout as String) as Map<String, dynamic>;
  final flutterRoot = versionJson['flutterRoot'] as String;

  final versions = parseFlutterAndroidVersions(
    File(
      '$flutterRoot/packages/flutter_tools/lib/src/android/gradle_utils.dart',
    ).readAsStringSync(),
  );

  var androidChanges = 0;

  final settingsFile = File(_settingsGradle);
  var settingsContent = settingsFile.readAsStringSync();
  for (final (pluginId, newVersion, label) in [
    ('com.android.application', versions.agp, 'AGP'),
    ('org.jetbrains.kotlin.android', versions.kotlin, 'Kotlin'),
  ]) {
    final current = readSettingsGradlePluginVersion(settingsContent, pluginId);
    if (current == null || current == newVersion) continue;
    print('  $label ($pluginId): $current -> $newVersion');
    settingsContent = patchSettingsGradlePlugin(
      settingsContent,
      pluginId,
      newVersion,
    );
    androidChanges++;
  }
  if (androidChanges > 0) settingsFile.writeAsStringSync(settingsContent);

  final wrapperFile = File(_gradleWrapper);
  var wrapperContent = wrapperFile.readAsStringSync();
  final currentGradle = readGradleWrapperVersion(wrapperContent);
  if (currentGradle != null && currentGradle != versions.gradle) {
    print('  Gradle: $currentGradle -> ${versions.gradle}');
    wrapperContent = patchGradleWrapper(wrapperContent, versions.gradle);
    wrapperFile.writeAsStringSync(wrapperContent);
    androidChanges++;
  }
  if (androidChanges == 0) {
    print('==> Android toolchain already up to date.');
  } else {
    print('==> Updated $androidChanges Android toolchain version(s).');
  }

  if (needsFlutterUpdate) {
    print(
      '''
==> Pin updated. Next steps:
      1. `fvm flutter pub get` to re-resolve against the new Dart SDK.
      2. Run the CI gates: fvm dart format ., fvm flutter analyze --fatal-infos,
         fvm flutter test.
      3. Review with: git diff $_fvmrc $_pubspec $_settingsGradle $_gradleWrapper''',
    );
  } else if (androidChanges > 0) {
    print('==> Done. Review with: git diff $_settingsGradle $_gradleWrapper');
  }
}

/// Resolves the stable release to pin to.
///
/// Reads the Linux manifest (what CI installs) and, when running on a different
/// OS, that platform's manifest too — then pins to the **lower** of the two
/// Flutter versions. During a staged rollout the manifests can briefly disagree;
/// taking the lower keeps the pin installable on both CI and this machine. The
/// chosen release's own bundled Dart version is used (never mixed across
/// manifests).
Future<(String flutter, String dart)> _resolveTargetStable() async {
  print('==> Fetching stable-channel release info');
  final linux = await _fetchLatestStable('linux');
  final localOs = _platformManifest();
  if (localOs == null || localOs == 'linux') {
    return linux;
  }

  final local = await _fetchLatestStable(localOs);
  if (local.$1 == linux.$1) return linux;

  // Pin to the lower of the two so both CI (Linux) and this OS can install it.
  // Stable releases normally land simultaneously across platforms, so a
  // mismatch is unusual — warn about it.
  final picked = isNewer(local.$1, linux.$1) ? local : linux;
  stderr.writeln(
    'WARNING: stable Flutter differs across manifests (Linux ${linux.$1} vs '
    '$localOs ${local.$1}) — normally they release together. Pinning the lower '
    '(${picked.$1}) so both CI and this OS can install it.',
  );
  return picked;
}

/// The releases-manifest name for the current platform, or `null` when the OS
/// isn't one Flutter publishes (then we fall back to the Linux/CI manifest).
String? _platformManifest() => switch (Platform.operatingSystem) {
  'linux' => 'linux',
  'macos' => 'macos',
  'windows' => 'windows',
  _ => null,
};

/// Fetches the latest stable-channel (Flutter, Dart SDK) versions from the
/// manifest for [os] and delegates parsing to [parseLatestStable].
Future<(String flutter, String dart)> _fetchLatestStable(String os) async {
  final url = Uri.parse(
    'https://storage.googleapis.com/flutter_infra_release/releases/'
    'releases_$os.json',
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      _fail('Manifest fetch failed for $os (HTTP ${response.statusCode}).');
    }
    final body = await response.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return parseLatestStable(data);
  } finally {
    client.close();
  }
}

String _readFvmrcFlutter() {
  final data =
      jsonDecode(File(_fvmrc).readAsStringSync()) as Map<String, dynamic>;
  final flutter = data['flutter'];
  if (flutter is! String) {
    _fail('No "flutter" version string in $_fvmrc.');
  }
  return flutter;
}

void _writeFvmrcFlutter(String version) {
  final data =
      jsonDecode(File(_fvmrc).readAsStringSync()) as Map<String, dynamic>;
  data['flutter'] = version;
  const encoder = JsonEncoder.withIndent('  ');
  File(_fvmrc).writeAsStringSync('${encoder.convert(data)}\n');
}

/// Reads the environment.sdk caret constraint (`^X.Y.Z`) from pubspec.yaml and
/// returns the version string, or null when the constraint is not a caret.
String? _readPubspecDart() {
  final raw = readYamlString(File(_pubspec).readAsStringSync(), [
    'environment',
    'sdk',
  ]);
  if (raw == null || !raw.startsWith('^')) return null;
  return raw.substring(1);
}

void _writePubspecDart(String version) {
  final content = File(_pubspec).readAsStringSync();
  final updated = setYamlValue(content, ['environment', 'sdk'], '^$version');
  File(_pubspec).writeAsStringSync(updated);
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
