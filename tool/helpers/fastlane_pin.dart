// Pure parsing logic for tool/update_gha.dart's fastlane check, extracted so it
// can be unit-tested without any file I/O or network access.

/// Matches a `gem "fastlane", "<constraint>"` line and captures the first digit
/// run inside the constraint (the major). Skips any leading operator
/// (`~>`, `>=`, …) and whitespace; accepts single or double quotes. Returns no
/// match for a versionless `gem "fastlane"` (treated as "unpinned").
final RegExp _fastlanePinRe = RegExp(
  '''gem\\s+['"]fastlane['"]\\s*,\\s*['"][^'"0-9]*([0-9]+)''',
);

/// Returns the pinned **major** version of `fastlane` declared in [gemfile]
/// content, or null when there is no fastlane pin with a version.
///
/// Handles `~> 2`, `~> 2.1`, `>= 2.0, < 3.0`, and exact `2.0.0` constraints,
/// single- or double-quoted.
int? parseFastlanePinMajor(String gemfile) {
  final m = _fastlanePinRe.firstMatch(gemfile);
  return m == null ? null : int.parse(m.group(1)!);
}
