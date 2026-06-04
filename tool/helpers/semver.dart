// Minimal semver comparison helpers extracted from tool/update_flutter.dart so
// they can be unit-tested without any file I/O or network access.

/// Returns true when [candidate] is strictly higher than [current].
///
/// Compares major.minor.patch only — pre-release and build-metadata suffixes
/// (`-beta.1`, `+123`) are stripped before comparison.
bool isNewer(String current, String candidate) {
  final a = parseSemver(current);
  final b = parseSemver(candidate);
  for (var i = 0; i < 3; i++) {
    if (b[i] != a[i]) return b[i] > a[i];
  }
  return false;
}

/// Parses a version string into a `[major, minor, patch]` list.
///
/// Pre-release (`-…`) and build (`+…`) suffixes are stripped. Missing parts
/// default to 0. Non-numeric parts are treated as 0.
List<int> parseSemver(String version) {
  final core = version.split('-').first.split('+').first;
  final parts = core.split('.');
  return [
    for (var i = 0; i < 3; i++)
      i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
  ];
}
