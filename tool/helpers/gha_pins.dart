// Pure parsing/rewriting logic for tool/update_gha.dart, extracted so it can be
// unit-tested without any network or file I/O.
//
// GitHub Actions in .github/**.yml are pinned either to a *major* tag
// (`uses: actions/checkout@v6`) or to a *specific version* tag
// (`uses: google/osv-scanner-action/osv-scanner-action@v2.3.8` — some actions,
// like OSV, never publish a moving `vN`). These helpers locate such pins
// (including subdirectory actions), pick the highest matching tag from the
// GitHub API's ref list, follow the API's paginated `Link` header, and rewrite
// a pin to a newer tag.

import 'semver.dart';

/// A parsed `uses:` pin. [repo] is the `owner/repo` to query for tags; [path] is
/// the full reference as written (repo + optional subdirectory, e.g.
/// `google/osv-scanner-action/osv-scanner-action`); [ref] is the version tag
/// including the leading `v` (`v6` or `v2.3.8`).
typedef ActionPin = ({String repo, String path, String ref});

/// Matches `uses: owner/repo[/subdir…]@vREF` in YAML, where `vREF` is a `v`
/// followed by digits/dots (`v6`, `v2.3.8`). Group 1 = `owner/repo`, group 2 =
/// the optional `/subdir…`, group 3 = the ref. Skips local `./…` actions and
/// SHA/branch pins (no `@v<digits>`); commented (`# uses:`) lines do not match.
final RegExp _usesRe = RegExp(
  r'^\s+(?:-\s+)?uses:\s+([\w.-]+/[\w.-]+)((?:/[\w.-]+)*)@(v\d+(?:\.\d+)*)(?:\s|$)',
  multiLine: true,
);

/// Matches a major-version tag ref like `refs/tags/v6` (no dots after the digit).
final RegExp _majorRefRe = RegExp(r'^refs/tags/v(\d+)$');

/// Matches a specific-version tag ref like `refs/tags/v2.3.8` (captures the bare
/// `2.3.8`). Bare major tags (`refs/tags/v2`) and pre-releases do not match.
final RegExp _versionRefRe = RegExp(r'^refs/tags/v(\d+\.\d+(?:\.\d+)?)$');

/// Parses every external `uses:` action pin in [content].
List<ActionPin> parseActionPins(String content) => [
  for (final m in _usesRe.allMatches(content))
    (repo: m.group(1)!, path: '${m.group(1)!}${m.group(2)!}', ref: m.group(3)!),
];

/// True when [ref] (e.g. `v6`) pins only a major version (no dots), as opposed
/// to a specific version like `v2.3.8`.
bool isMajorRef(String ref) => !ref.contains('.');

/// Returns the highest major version among [refNames] that are bare `vN` tags
/// (`refs/tags/v6`), or null when none qualify. Dotted tags (`refs/tags/v6.1.0`)
/// and non-version tags are ignored.
int? highestMajorTag(Iterable<String> refNames) {
  int? highest;
  for (final name in refNames) {
    final m = _majorRefRe.firstMatch(name);
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    if (highest == null || n > highest) highest = n;
  }
  return highest;
}

/// Returns the highest specific `vX.Y[.Z]` version among [refNames] as the bare
/// semver string (`2.3.8`), or null when none match. Compared with [isNewer], so
/// `2.10.0` beats `2.9.0`.
String? highestVersionTag(Iterable<String> refNames) {
  String? highest;
  for (final name in refNames) {
    final m = _versionRefRe.firstMatch(name);
    if (m == null) continue;
    final v = m.group(1)!;
    if (highest == null || isNewer(highest, v)) highest = v;
  }
  return highest;
}

/// Extracts the `rel="next"` URL from a GitHub API pagination [linkHeader], or
/// null when there is no next page (or the header is null/empty).
String? parseNextLink(String? linkHeader) {
  if (linkHeader == null) return null;
  for (final part in linkHeader.split(',')) {
    final segs = part.trim().split(';');
    if (segs.length == 2 && segs[1].trim() == 'rel="next"') {
      final url = segs[0].trim();
      return url.substring(1, url.length - 1); // strip the surrounding < >
    }
  }
  return null;
}

/// Rewrites the `uses: <path>@v…` pin in [content] to `@<newRef>`, leaving other
/// actions untouched. Anchored on the full [path] (so subdirectory actions and
/// look-alike repos are unaffected) and matches the whole `v…` ref, so it works
/// for both bare-major (`v6`) and specific-version (`v2.3.8`) pins. [newRef]
/// includes the leading `v` (`v9`, `v2.4.0`).
String applyPinBump(String content, String path, String newRef) {
  final re = RegExp(
    '(uses:\\s+${RegExp.escape(path)})@v[\\d.]+(?=\\s|\$)',
    multiLine: true,
  );
  return content.replaceAllMapped(re, (m) => '${m.group(1)}@$newRef');
}

/// Matches a pinned Ubuntu runner like `runs-on: ubuntu-24.04` (captures the
/// `(major, minor)`). `ubuntu-latest` and non-Ubuntu runners do not match.
final RegExp _ubuntuRunnerRe = RegExp(r'runs-on:\s*ubuntu-(\d+)\.(\d+)');

/// Parses the pinned Ubuntu runner versions in [content] (a workflow YAML),
/// each as a `(major, minor)` pair. `ubuntu-latest` (and macOS/other runners)
/// are ignored.
Set<(int, int)> parseUbuntuRunners(String content) => {
  for (final m in _ubuntuRunnerRe.allMatches(content))
    (int.parse(m.group(1)!), int.parse(m.group(2)!)),
};

/// Matches an x64 Ubuntu image readme name in `actions/runner-images`
/// (`images/ubuntu/Ubuntu2404-Readme.md` → 24.04). The `-Arm64-` variants do
/// not match, so the project's x64 `ubuntu-NN.NN` pins compare like-for-like.
final RegExp _ubuntuImageRe = RegExp(r'^Ubuntu(\d{2})(\d{2})-Readme\.md$');

/// Returns the highest Ubuntu version among [fileNames] (the entry names of the
/// runner-images `images/ubuntu/` directory), or null when none match.
(int, int)? highestUbuntuImage(Iterable<String> fileNames) {
  (int, int)? highest;
  for (final name in fileNames) {
    final m = _ubuntuImageRe.firstMatch(name);
    if (m == null) continue;
    final v = (int.parse(m.group(1)!), int.parse(m.group(2)!));
    if (highest == null || ubuntuIsNewer(v, highest)) highest = v;
  }
  return highest;
}

/// True when Ubuntu version [candidate] is newer than [current] (major first,
/// then minor) — e.g. `(26, 4)` is newer than `(24, 4)`.
bool ubuntuIsNewer((int, int) candidate, (int, int) current) =>
    candidate.$1 != current.$1
    ? candidate.$1 > current.$1
    : candidate.$2 > current.$2;
