#!/usr/bin/env dart
// ignore_for_file: avoid_print

// Check for (and optionally apply) the latest **stable**-channel Flutter SDK
// release, keeping the project's version pin in lock-step:
//   1. Fetch the official Flutter releases manifest and read the current
//      stable-channel release (its Flutter version + bundled Dart SDK version).
//   2. Compare against the pin in `.fvmrc` (the single source of truth — CI's
//      `subosito/flutter-action` installs `flutter-version-file: .fvmrc` on
//      `channel: stable`).
//   3. If a newer stable exists, rewrite `.fvmrc` to the new Flutter version and
//      bump the Dart `sdk:` lower-bound in `pubspec.yaml` to the bundled Dart
//      version (only when it's a caret constraint — explicit pins are left
//      alone, matching `tool/update_deps.sh`).
//
// Never downgrades: if the pin is already at/ahead of the latest stable, it's a
// no-op. The local SDK is not touched — this only moves the pin; install the new
// version afterwards (`fvm install`, or `flutter upgrade` on the stable channel)
// and re-run the CI gates.
//
// Usage (either form works):
//   ./tool/update_flutter.dart [--check]        # executable (shebang)
//   dart run tool/update_flutter.dart [--check] # check + apply, or --check only

import 'dart:convert';
import 'dart:io';

const _fvmrc = '.fvmrc';
const _pubspec = 'pubspec.yaml';

/// Matches the environment Dart constraint `  sdk: ^X.Y.Z`. Caret-only, so the
/// `sdk: flutter` style dependency entries (no caret) are left untouched.
final RegExp _dartConstraint = RegExp(
  r'^(\s*sdk:\s*)\^([0-9][^\s]*)',
  multiLine: true,
);

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  if (args.length > 1 || (args.length == 1 && !checkOnly)) {
    stderr.writeln('Usage: dart run tool/update_flutter.dart [--check]');
    exit(2);
  }
  if (!File(_fvmrc).existsSync() || !File(_pubspec).existsSync()) {
    stderr.writeln('Run from the repo root (needs $_fvmrc + $_pubspec).');
    exit(1);
  }

  final (latestFlutter, latestDart) = await _resolveTargetStable();
  final currentFlutter = _readFvmrcFlutter();
  final currentDart = _readPubspecDart();

  print('    Pinned : Flutter $currentFlutter  (Dart ${currentDart ?? '?'})');
  print('    Latest : Flutter $latestFlutter  (Dart $latestDart, stable)');

  if (!_isNewer(currentFlutter, latestFlutter)) {
    print('==> Already on the latest stable Flutter ($currentFlutter).');
    return;
  }

  print('==> Update available: Flutter $currentFlutter -> $latestFlutter');
  if (checkOnly) {
    print('    (--check) Not applying. Run without --check to update the pin.');
    exit(1);
  }

  _writeFvmrcFlutter(latestFlutter);
  print('    $_fvmrc: flutter $currentFlutter -> $latestFlutter');
  if (currentDart != null && currentDart != latestDart) {
    _writePubspecDart(latestDart);
    print('    $_pubspec: sdk ^$currentDart -> ^$latestDart');
  }

  print('''
==> Pin updated. Next steps:
      1. Install the new SDK (`fvm install`, or `flutter upgrade` on the stable
         channel) so your local Flutter matches the pin.
      2. `flutter pub get` to re-resolve against the new Dart SDK.
      3. Run the CI gates: dart format, flutter analyze --fatal-infos, flutter test.
      4. Review with: git diff $_fvmrc $_pubspec''');
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
  final linux = await _latestStable('linux');
  final localOs = _platformManifest();
  if (localOs == null || localOs == 'linux') {
    return linux;
  }

  final local = await _latestStable(localOs);
  if (local.$1 == linux.$1) return linux;

  // Pin to the lower of the two so both CI (Linux) and this OS can install it.
  // Stable releases normally land simultaneously across platforms, so a
  // mismatch is unusual — warn about it.
  final picked = _isNewer(local.$1, linux.$1) ? local : linux;
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

/// Latest stable-channel (Flutter, Dart SDK) versions from one platform manifest.
Future<(String flutter, String dart)> _latestStable(String os) async {
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
    final stableHash =
        (data['current_release'] as Map<String, dynamic>)['stable'] as String;
    for (final entry in data['releases'] as List<dynamic>) {
      final release = entry as Map<String, dynamic>;
      if (release['hash'] == stableHash) {
        // `dart_sdk_version` can carry a channel suffix (e.g. "3.9.0 (build …)");
        // keep only the leading semver for the pubspec constraint.
        final dart = (release['dart_sdk_version'] as String).split(' ').first;
        return (release['version'] as String, dart);
      }
    }
    _fail('Stable release $stableHash not found in $os manifest.');
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

String? _readPubspecDart() =>
    _dartConstraint.firstMatch(File(_pubspec).readAsStringSync())?.group(2);

void _writePubspecDart(String version) {
  final content = File(_pubspec).readAsStringSync();
  final updated = content.replaceFirstMapped(
    _dartConstraint,
    (m) => '${m.group(1)}^$version',
  );
  File(_pubspec).writeAsStringSync(updated);
}

/// Returns true when [candidate] is a strictly higher semver than [current]
/// (compares major.minor.patch only — pre-release suffixes are ignored).
bool _isNewer(String current, String candidate) {
  final a = _semver(current);
  final b = _semver(candidate);
  for (var i = 0; i < 3; i++) {
    if (b[i] != a[i]) return b[i] > a[i];
  }
  return false;
}

List<int> _semver(String version) {
  final core = version.split('-').first.split('+').first;
  final parts = core.split('.');
  return [
    for (var i = 0; i < 3; i++)
      i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
  ];
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
