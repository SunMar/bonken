#!/usr/bin/env -S fvm dart
// ignore_for_file: avoid_print

// Check the project's GitHub-Actions CI toolchain for available updates:
//
//   1. Pinned GitHub Actions (`uses: owner/repo[/sub]@v…`) — reports a newer tag
//      and, unless `--check` is given, APPLIES the bump in place. An action
//      pinned to a bare major (`@v6`) tracks the highest major tag; one pinned
//      to a specific version (`@v2.3.8`, e.g. OSV, which has no moving `vN`)
//      tracks the highest `vX.Y.Z` tag.
//   2. fastlane (`gem "fastlane", "~> N"` in the Gemfiles) — REPORTS a new major
//      only; a major bump may need Fastfile changes, so it stays manual.
//   3. The Ubuntu runner (`runs-on: ubuntu-N.N`) — REPORTS a newer LTS image
//      only; bumping the OS is deliberate (package names etc. can change).
//   4. Ruby (`ruby-version: 'X.Y'` in workflow YAML) — REPORTS a newer release
//      cycle only; bumping Ruby is deliberate (API/gem compat can change).
//
// Only the GitHub Actions are ever written; fastlane, the runner, and Ruby are
// report-only heads-ups, matching how the tooling/OS were pinned on purpose.
// The parsing/compare logic lives in tool/helpers/{gha_pins,fastlane_pin,
// semver}.dart (unit-tested); this script is the I/O + network glue.
//
// Set GITHUB_TOKEN in the environment to avoid API rate limits (60/h
// unauthenticated → 5 000/h authenticated).
//
// Usage:
//   ./tool/update_gha.dart [--check]            # executable (shebang)
//   fvm dart run tool/update_gha.dart [--check] # check + apply actions, or --check only

import 'dart:convert';
import 'dart:io';

import 'helpers/fastlane_pin.dart';
import 'helpers/gha_pins.dart';
import 'helpers/ruby_pin.dart';
import 'helpers/semver.dart';

const _gemfiles = ['android/Gemfile', 'ios/Gemfile'];

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  if (args.length > 1 || (args.length == 1 && !checkOnly)) {
    stderr.writeln('Usage: dart run tool/update_gha.dart [--check]');
    exit(2);
  }

  if (!Directory('.github').existsSync()) {
    stderr.writeln('Run from the repo root (needs a .github/ directory).');
    exit(1);
  }

  final yamlFiles = _collectYaml();
  if (yamlFiles.isEmpty) {
    stderr.writeln('No YAML files found under .github/.');
    exit(1);
  }

  final token = Platform.environment['GITHUB_TOKEN'];
  final client = HttpClient();

  // Whether anything still needs the user's attention after this run. In
  // --check mode that is any available update; in apply mode the actions are
  // bumped in place, so only the report-only items (fastlane, runner) count.
  var pending = false;
  try {
    pending |= await _checkActions(yamlFiles, token, client, checkOnly);
    pending |= await _checkFastlane(client);
    pending |= await _checkUbuntu(yamlFiles, token, client);
    pending |= await _checkRuby(yamlFiles, client);
  } finally {
    client.close();
  }

  exit(pending ? 1 : 0);
}

// ---------------------------------------------------------------------------
// 1. GitHub Actions — report + (unless --check) apply newer tags.
// ---------------------------------------------------------------------------

/// Returns whether any action still needs attention afterwards (true only in
/// [checkOnly] mode — apply mode resolves them by writing the bump).
Future<bool> _checkActions(
  List<String> yamlFiles,
  String? token,
  HttpClient client,
  bool checkOnly,
) async {
  // Keyed by the full `uses:` path so a subdirectory action is one entry.
  final byPath = <String, _ActionUsage>{};
  for (final file in yamlFiles) {
    final content = File(file).readAsStringSync();
    for (final pin in parseActionPins(content)) {
      final usage = byPath[pin.path] ??= _ActionUsage(pin.repo, pin.path);
      usage.files.add(file);
      usage.refs.add(pin.ref);
    }
  }

  print('==> GitHub Actions');
  if (byPath.isEmpty) {
    print('  (no external actions found)');
    return false;
  }

  var updates = 0;
  for (final usage
      in byPath.values.toList()..sort((a, b) => a.path.compareTo(b.path))) {
    final refs = await _fetchTagRefs(usage.repo, token, client);
    if (refs == null) continue; // already warned

    // A specific-version pin (any ref with a dot) tracks the highest vX.Y.Z
    // tag; a bare-major pin tracks the highest vN tag.
    final bump = usage.refs.any((r) => !isMajorRef(r))
        ? _versionBump(usage, refs)
        : _majorBump(usage, refs);
    if (bump == null) continue; // up to date, or warned

    final (current, latest) = bump;
    print('  ${usage.path}: $current -> $latest');
    updates++;

    if (!checkOnly) {
      for (final file in usage.files) {
        final original = File(file).readAsStringSync();
        final updated = applyPinBump(original, usage.path, latest);
        if (updated != original) File(file).writeAsStringSync(updated);
      }
    }
  }

  if (updates == 0) {
    print('  All actions up to date.');
    return false;
  }
  if (checkOnly) {
    print(
      '  $updates action(s) have a newer tag — run without --check to apply.',
    );
    return true;
  }
  print('  Updated $updates action(s). Review with: git diff .github/');
  return false;
}

/// `(currentRef, latestRef)` when the bare-major-pinned [usage] is behind the
/// highest `vN` tag, else null (after printing the up-to-date / warning line).
(String, String)? _majorBump(_ActionUsage usage, List<String> refs) {
  final current = usage.refs
      .map((r) => int.parse(r.substring(1)))
      .reduce((a, b) => a > b ? a : b);
  final latest = highestMajorTag(refs);
  if (latest == null) {
    stderr.writeln(
      '  WARNING: ${usage.repo} has no vN major-version tags — skipping.',
    );
    return null;
  }
  if (latest <= current) {
    print('  ${usage.path}: v$current (up to date)');
    return null;
  }
  return ('v$current', 'v$latest');
}

/// `(currentRef, latestRef)` when the version-pinned [usage] is behind the
/// highest `vX.Y.Z` tag, else null (after printing the up-to-date / warning line).
(String, String)? _versionBump(_ActionUsage usage, List<String> refs) {
  final current = usage.refs
      .map((r) => r.substring(1))
      .reduce((a, b) => isNewer(a, b) ? b : a);
  final latest = highestVersionTag(refs);
  if (latest == null) {
    stderr.writeln(
      '  WARNING: ${usage.repo} has no vX.Y.Z version tags — skipping.',
    );
    return null;
  }
  if (!isNewer(current, latest)) {
    print('  ${usage.path}: v$current (up to date)');
    return null;
  }
  return ('v$current', 'v$latest');
}

// ---------------------------------------------------------------------------
// 2. fastlane — report-only (never written).
// ---------------------------------------------------------------------------

/// Returns whether a new fastlane MAJOR is available upstream.
Future<bool> _checkFastlane(HttpClient client) async {
  print('==> fastlane');

  final pins = <String, int>{};
  for (final path in _gemfiles) {
    if (!File(path).existsSync()) {
      print('  WARNING: $path not found — skipping.');
      return false;
    }
    final major = parseFastlanePinMajor(File(path).readAsStringSync());
    if (major == null) {
      print('  WARNING: no versioned fastlane pin in $path — skipping.');
      return false;
    }
    pins[path] = major;
  }

  final majors = pins.values.toSet();
  if (majors.length > 1) {
    final detail = pins.entries.map((e) => '${e.key}=~>${e.value}').join(', ');
    print('  WARNING: Gemfiles pin different majors ($detail) — skipping.');
    return false;
  }
  final pinnedMajor = majors.single;

  final latest = await _fetchJsonVersion(
    client,
    Uri.parse('https://rubygems.org/api/v1/versions/fastlane/latest.json'),
  );
  if (latest == null) return false; // already warned
  final latestMajor = parseSemver(latest).first;

  if (latestMajor <= pinnedMajor) {
    print('  ~>$pinnedMajor (latest $latest) — up to date.');
    return false;
  }
  print(
    '  ~>$pinnedMajor -> $latestMajor available (latest $latest). Review the '
    'changelog, then bump `gem "fastlane", "~> $latestMajor"` in '
    '${_gemfiles.join(' + ')}.',
  );
  return true;
}

// ---------------------------------------------------------------------------
// 3. Ubuntu runner — report-only (never written).
// ---------------------------------------------------------------------------

/// Returns whether a newer Ubuntu LTS runner image is available than the oldest
/// `runs-on: ubuntu-N.N` pin across all workflows (oldest, so a straggling
/// workflow is flagged too).
Future<bool> _checkUbuntu(
  List<String> yamlFiles,
  String? token,
  HttpClient client,
) async {
  print('==> Ubuntu runner');

  final pinned = <(int, int)>{};
  for (final file in yamlFiles) {
    pinned.addAll(parseUbuntuRunners(File(file).readAsStringSync()));
  }
  if (pinned.isEmpty) {
    print('  (no pinned ubuntu-N.N runners found)');
    return false;
  }
  final oldest = pinned.reduce((a, b) => ubuntuIsNewer(a, b) ? b : a);
  final spread = pinned.length == 1
      ? ''
      : ' (pinned: ${(pinned.toList()..sort(_byUbuntu)).map(_ubuntu).join(', ')})';

  final names = await _fetchRunnerImageNames(token, client);
  if (names == null) return false; // already warned
  final latest = highestUbuntuImage(names);
  if (latest == null) {
    print('  WARNING: could not determine the latest Ubuntu image — skipping.');
    return false;
  }

  if (!ubuntuIsNewer(latest, oldest)) {
    print(
      '  ${_ubuntu(oldest)} (latest ${_ubuntu(latest)}) — up to date.$spread',
    );
    return false;
  }
  print(
    '  ${_ubuntu(oldest)} -> ${_ubuntu(latest)} available$spread. Confirm it is '
    'GA, then bump `runs-on:` across .github/workflows/.',
  );
  return true;
}

String _ubuntu((int, int) v) =>
    'ubuntu-${v.$1}.${v.$2.toString().padLeft(2, '0')}';

int _byUbuntu((int, int) a, (int, int) b) =>
    ubuntuIsNewer(a, b) ? -1 : (ubuntuIsNewer(b, a) ? 1 : 0);

// ---------------------------------------------------------------------------
// 4. Ruby — report-only (never written).
// ---------------------------------------------------------------------------

/// Returns whether a newer Ruby major.minor cycle is available than the pinned
/// `ruby-version: 'X.Y'` across all workflows.
///
/// Queries `ruby-builder-versions.json` from the same branch of `ruby/setup-ruby`
/// that the workflows pin (e.g. `v1`), so the supported-versions list matches
/// the action version in use.
Future<bool> _checkRuby(List<String> yamlFiles, HttpClient client) async {
  print('==> Ruby');

  // Collect ruby-version pins and the ruby/setup-ruby action ref in one pass.
  final pins = <String, (int, int)>{};
  String? setupRubyRef;
  for (final file in yamlFiles) {
    final content = File(file).readAsStringSync();
    final pin = parseRubyVersionPin(content);
    if (pin != null) pins[file] = pin;
    setupRubyRef ??= parseActionPins(
      content,
    ).where((p) => p.repo == 'ruby/setup-ruby').map((p) => p.ref).firstOrNull;
  }

  if (pins.isEmpty) {
    print('  (no ruby-version pins found)');
    return false;
  }

  final versions = pins.values.toSet();
  if (versions.length > 1) {
    final detail = pins.entries
        .map((e) => '${e.key}=${e.value.$1}.${e.value.$2}')
        .join(', ');
    print(
      '  WARNING: workflows pin different Ruby versions ($detail) — skipping.',
    );
    return false;
  }
  final pinned = versions.single;

  final ref = setupRubyRef ?? 'master';
  final latest = await _fetchLatestRubyCycle(client, ref);
  if (latest == null) return false;

  if (!rubyIsNewer(latest, pinned)) {
    print(
      '  ${pinned.$1}.${pinned.$2} (latest ${latest.$1}.${latest.$2}) — up to date.',
    );
    return false;
  }
  print(
    '  ${pinned.$1}.${pinned.$2} -> ${latest.$1}.${latest.$2} available. '
    'Bump `ruby-version:` in .github/workflows/.',
  );
  return true;
}

/// Fetches the latest stable Ruby major.minor cycle from `ruby-builder-versions.json`
/// at the given [ref] (branch/tag) of `ruby/setup-ruby`, or null (with a
/// warning) on failure.
Future<(int, int)?> _fetchLatestRubyCycle(HttpClient client, String ref) async {
  final request = await client.getUrl(
    Uri.parse(
      'https://raw.githubusercontent.com/ruby/setup-ruby/$ref/ruby-builder-versions.json',
    ),
  );
  request.headers.set('User-Agent', 'tool/update_gha.dart');

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    stderr.writeln(
      '  WARNING: ruby/setup-ruby/$ref returned HTTP ${response.statusCode} — skipping.',
    );
    return null;
  }
  final latest = parseLatestRubyBuilderCycle(body);
  if (latest == null) {
    stderr.writeln(
      '  WARNING: could not parse ruby-builder-versions.json — skipping.',
    );
  }
  return latest;
}

// ---------------------------------------------------------------------------
// Shared I/O helpers.
// ---------------------------------------------------------------------------

List<String> _collectYaml() {
  bool isYaml(FileSystemEntity e) =>
      e is File && (e.path.endsWith('.yml') || e.path.endsWith('.yaml'));

  return [
    if (Directory('.github/workflows').existsSync())
      ...Directory(
        '.github/workflows',
      ).listSync().where(isYaml).map((e) => e.path),
    if (Directory('.github/actions').existsSync())
      ...Directory(
        '.github/actions',
      ).listSync(recursive: true).where(isYaml).map((e) => e.path),
  ];
}

/// Paginates the `v…` tag refs for [repo] (`refs/tags/v2.3.8`, …), or `null`
/// (with a warning) if it could not be queried.
Future<List<String>?> _fetchTagRefs(
  String repo,
  String? token,
  HttpClient client,
) async {
  final refs = <String>[];
  String? nextUrl =
      'https://api.github.com/repos/$repo/git/matching-refs/tags/v'
      '?per_page=100';

  while (nextUrl != null) {
    final request = await client.getUrl(Uri.parse(nextUrl));
    _githubHeaders(request, token);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode == 404) {
      stderr.writeln('  WARNING: $repo not found on GitHub — skipping.');
      return null;
    }
    if (response.statusCode != 200) {
      _fail(
        'GitHub API returned HTTP ${response.statusCode} for $repo:\n$body',
      );
    }

    for (final ref in jsonDecode(body) as List<dynamic>) {
      refs.add((ref as Map<String, dynamic>)['ref'] as String);
    }
    nextUrl = parseNextLink(response.headers.value('link'));
  }
  return refs;
}

/// Lists the entry names under `actions/runner-images` `images/ubuntu/`, or
/// `null` (with a warning) on failure.
Future<List<String>?> _fetchRunnerImageNames(
  String? token,
  HttpClient client,
) async {
  final request = await client.getUrl(
    Uri.parse(
      'https://api.github.com/repos/actions/runner-images/contents/images/ubuntu',
    ),
  );
  _githubHeaders(request, token);

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    stderr.writeln(
      '  WARNING: runner-images API returned HTTP ${response.statusCode} '
      '— skipping.',
    );
    return null;
  }
  return [
    for (final e in jsonDecode(body) as List<dynamic>)
      (e as Map<String, dynamic>)['name'] as String,
  ];
}

/// GETs a `{"version": "X.Y.Z"}` JSON document (e.g. the RubyGems latest.json
/// endpoint) and returns the version string, or `null` (with a warning).
Future<String?> _fetchJsonVersion(HttpClient client, Uri url) async {
  final request = await client.getUrl(url);
  request.headers.set('User-Agent', 'tool/update_gha.dart');

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    stderr.writeln(
      '  WARNING: ${url.host} returned HTTP ${response.statusCode} — skipping.',
    );
    return null;
  }
  final version = (jsonDecode(body) as Map<String, dynamic>)['version'];
  return version is String ? version : null;
}

void _githubHeaders(HttpClientRequest request, String? token) {
  request.headers
    ..set('Accept', 'application/vnd.github+json')
    ..set('X-GitHub-Api-Version', '2022-11-28')
    ..set('User-Agent', 'tool/update_gha.dart');
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
}

class _ActionUsage {
  _ActionUsage(this.repo, this.path);

  /// `owner/repo` queried for tags.
  final String repo;

  /// Full `uses:` path (repo + optional subdirectory), used to rewrite the pin.
  final String path;
  final Set<String> files = {};

  /// Pinned refs seen for this action (e.g. `{v6}` or `{v2.3.8}`).
  final Set<String> refs = {};
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
