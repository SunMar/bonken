// Pure parsing logic for tool/update_gha.dart's Ruby version check, extracted
// so it can be unit-tested without any file I/O or network access.

import 'dart:convert';

/// Matches `ruby-version: 'X.Y'` (single/double quotes, or unquoted).
final RegExp _rubyVersionPinRe = RegExp(
  r"""ruby-version:\s+['"]?(\d+\.\d+)['"]?""",
);

/// Returns the pinned `(major, minor)` Ruby cycle from a YAML [content]
/// string, or null when no `ruby-version:` key is found.
(int, int)? parseRubyVersionPin(String content) {
  final m = _rubyVersionPinRe.firstMatch(content);
  if (m == null) return null;
  final parts = m.group(1)!.split('.');
  return (int.parse(parts[0]), int.parse(parts[1]));
}

/// Matches a plain stable `X.Y.Z` version string — no preview, rc, or named
/// suffix (`head`, `debug`, `asan`, …).
final RegExp _stableRe = RegExp(r'^\d+\.\d+\.\d+$');

/// Returns the latest stable Ruby `(major, minor)` cycle from a
/// `ruby-builder-versions.json` response body (the file at the root of
/// `ruby/setup-ruby`), or null if none could be parsed.
///
/// Only stable `X.Y.Z` entries under the `"ruby"` key are considered —
/// previews, release candidates, and named builds (`head`, `debug`, …) are
/// skipped.
(int, int)? parseLatestRubyBuilderCycle(String responseBody) {
  final Map<String, dynamic> root;
  try {
    root = jsonDecode(responseBody) as Map<String, dynamic>;
  } on FormatException {
    return null;
  }
  final versions = root['ruby'] as List<dynamic>?;
  if (versions == null) return null;

  (int, int)? latest;
  for (final entry in versions) {
    final v = entry as String?;
    if (v == null || !_stableRe.hasMatch(v)) continue;
    final parts = v.split('.');
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    if (major == null || minor == null) continue;
    final cycle = (major, minor);
    if (latest == null || rubyIsNewer(cycle, latest)) latest = cycle;
  }
  return latest;
}

/// True when Ruby cycle [candidate] is strictly newer than [current] (major
/// first, then minor) — e.g. `(4, 1)` is newer than `(4, 0)`.
bool rubyIsNewer((int, int) candidate, (int, int) current) =>
    candidate.$1 != current.$1
    ? candidate.$1 > current.$1
    : candidate.$2 > current.$2;
