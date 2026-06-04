#!/usr/bin/env -S fvm dart
// ignore_for_file: avoid_print

// Upgrade all locally-bundled fonts in lock-step with their upstream sources.
//
// This script is the single entry point for refreshing the fonts that ship with
// the app, all sourced through the google_fonts package:
//
//   - Roboto (Regular/Medium/Bold)  — the app's text theme.
//   - Arimo  (Regular)              — the card-suit glyphs ♠ ♥ ♦ ♣
//                                     (Roboto lacks those codepoints).
//
// google_fonts is pinned to an exact version (no caret) and runs with
// allowRuntimeFetching=false, so the bundled .ttf files under
// assets/google_fonts/<version>/ MUST match the package version exactly.
// The same TTFs are reused by tool/generate_icons.sh's fontconfig sandbox
// to rasterize the icon SVGs.
//
// Usage:
//   fvm dart run tool/update_fonts.dart   # or: ./tool/update_fonts.dart

import 'dart:convert';
import 'dart:io';

import 'helpers/google_fonts_parser.dart';
import 'helpers/pubspec_lock.dart';
import 'helpers/pubspec_yaml.dart';

const _pubspec = 'pubspec.yaml';
const _pubspecLock = 'pubspec.lock';
const _assetsPrefix = 'assets/google_fonts/';
const _arimoLicenseUrl =
    'https://raw.githubusercontent.com/google/fonts/main/ofl/arimo/OFL.txt';

Future<void> main() async {
  if (!File(_pubspec).existsSync() || !File(_pubspecLock).existsSync()) {
    stderr.writeln('Run from the repo root (needs $_pubspec + $_pubspecLock).');
    exit(1);
  }

  await _updateGoogleFonts();

  print('\nDone. Review the diff and commit:');
  print('  git status');
  print('  git diff $_pubspec');
}

Future<void> _updateGoogleFonts() async {
  print('='.padRight(58, '='));
  print(' google_fonts (Roboto + Arimo)');
  print('='.padRight(58, '='));

  final pubspecContent = File(_pubspec).readAsStringSync();
  final oldVersion = _readGoogleFontsPin(pubspecContent);
  if (oldVersion == null) {
    _fail('Could not find a google_fonts pin in $_pubspec');
  }
  print('Current pinned google_fonts version: $oldVersion');

  // 1. Relax to caret so pub can resolve a newer compatible release.
  final relaxed = setYamlValue(pubspecContent, [
    'dependencies',
    'google_fonts',
  ], '^$oldVersion');
  File(_pubspec).writeAsStringSync(relaxed);

  // Restore exact pin on any failure path.
  Future<void> restore([String? v]) async {
    final content = File(_pubspec).readAsStringSync();
    File(_pubspec).writeAsStringSync(
      setYamlValue(content, ['dependencies', 'google_fonts'], v ?? oldVersion),
    );
  }

  String newVersion;
  try {
    print('Relaxing constraint to ^$oldVersion and upgrading…');
    final result = await Process.run('fvm', [
      'flutter',
      'pub',
      'upgrade',
      'google_fonts',
    ]);
    if (result.exitCode != 0) {
      await restore();
      _fail('fvm flutter pub upgrade google_fonts failed:\n${result.stderr}');
    }

    // 2. Read the resolved version from pubspec.lock.
    final resolvedVersion = parseLockfileVersions(
      File(_pubspecLock).readAsStringSync(),
    )['google_fonts'];
    if (resolvedVersion == null) {
      await restore();
      _fail('Could not read resolved google_fonts version from $_pubspecLock');
    }
    newVersion = resolvedVersion;

    // 3. Re-pin to resolved version.
    final pinned = setYamlValue(File(_pubspec).readAsStringSync(), [
      'dependencies',
      'google_fonts',
    ], newVersion);
    File(_pubspec).writeAsStringSync(pinned);
  } catch (_) {
    await restore();
    rethrow;
  }

  if (newVersion == oldVersion) {
    print('Already up to date (google_fonts $oldVersion). No asset changes.');
    return;
  }
  print('Upgrading google_fonts: $oldVersion -> $newVersion');

  // 4. Locate the new package source in the pub cache.
  final pkgDir = _pubCacheDir(newVersion);
  if (!Directory(pkgDir).existsSync()) {
    _fail('google_fonts package not found at $pkgDir');
  }

  // 5. Parse hashes and download TTFs.
  final outDir = '$_assetsPrefix$newVersion';
  Directory(outDir).createSync(recursive: true);

  await _downloadRoboto(pkgDir, outDir);
  await _downloadArimo(pkgDir, outDir);
  await _downloadArimoLicense(outDir);

  // 6. Update the asset path in pubspec.yaml.
  final updated = replaceYamlListEntry(
    File(_pubspec).readAsStringSync(),
    ['flutter', 'assets'],
    (entry) => entry.startsWith(_assetsPrefix),
    '$_assetsPrefix$newVersion/',
  );
  File(_pubspec).writeAsStringSync(updated);

  // 7. Delete the old asset directory.
  final oldDir = '$_assetsPrefix$oldVersion';
  if (oldDir != outDir && Directory(oldDir).existsSync()) {
    print('Removing old asset directory: $oldDir');
    Directory(oldDir).deleteSync(recursive: true);
  }

  print('google_fonts is now pinned to $newVersion with matching assets.');
}

// ---------------------------------------------------------------------------
// Font downloads
// ---------------------------------------------------------------------------

Future<void> _downloadRoboto(String pkgDir, String outDir) async {
  final src = '$pkgDir/lib/src/google_fonts_parts/part_r.dart';
  final source = File(src).readAsStringSync();
  final variants = parseFontVariants(source, 'roboto');

  for (final (weight: w, label: label) in [
    (weight: FontWeight.w400, label: 'Regular'),
    (weight: FontWeight.w500, label: 'Medium'),
    (weight: FontWeight.w700, label: 'Bold'),
  ]) {
    final hash = hashForWeight(variants, w);
    await _downloadTtf(hash, '$outDir/Roboto-$label.ttf');
  }
}

Future<void> _downloadArimo(String pkgDir, String outDir) async {
  final src = '$pkgDir/lib/src/google_fonts_parts/part_a.dart';
  final source = File(src).readAsStringSync();
  final variants = parseFontVariants(source, 'arimo');
  final hash = hashForWeight(variants, FontWeight.w400);
  await _downloadTtf(hash, '$outDir/Arimo-Regular.ttf');
}

Future<void> _downloadTtf(String hash, String dest) async {
  final url = Uri.parse('https://fonts.gstatic.com/s/a/$hash.ttf');
  print('  -> $dest  ($hash)');
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      _fail('TTF download failed (HTTP ${response.statusCode}): $url');
    }
    final bytes = await response.fold<List<int>>(
      [],
      (acc, chunk) => acc..addAll(chunk),
    );
    File(dest).writeAsBytesSync(bytes);
  } finally {
    client.close();
  }
}

Future<void> _downloadArimoLicense(String outDir) async {
  final dest = '$outDir/Arimo-LICENSE.txt';
  print('  -> $dest  (Arimo SIL OFL from google/fonts repo)');
  final client = HttpClient();
  try {
    final url = Uri.parse(_arimoLicenseUrl);
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      _fail('License download failed (HTTP ${response.statusCode}): $url');
    }
    final text = await response.transform(utf8.decoder).join();
    File(dest).writeAsStringSync(text);
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Reads the pinned `google_fonts` version from pubspec.yaml.
/// Returns null when not found or when it's a caret constraint.
String? _readGoogleFontsPin(String pubspecContent) {
  final raw = readYamlString(pubspecContent, ['dependencies', 'google_fonts']);
  if (raw == null || raw.startsWith('^')) return null;
  return raw;
}

String _pubCacheDir(String version) =>
    '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/google_fonts-$version';

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
