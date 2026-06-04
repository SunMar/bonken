// Pure parsing logic for the Flutter releases manifest JSON, extracted from
// tool/update_flutter.dart so it can be unit-tested with fixture data without
// any network access.

/// Parses the stable (Flutter, Dart SDK) version pair from the JSON body of
/// a Flutter releases manifest (`releases_<os>.json`).
///
/// The `dart_sdk_version` field may carry a build suffix
/// (`"3.9.0 (build …)"`) — only the leading semver is returned.
///
/// Throws [StateError] when the stable hash is not found in the releases list
/// (should not happen for a valid manifest).
(String flutter, String dart) parseLatestStable(Map<String, dynamic> data) {
  final stableHash =
      (data['current_release'] as Map<String, dynamic>)['stable'] as String;
  for (final entry in data['releases'] as List<dynamic>) {
    final release = entry as Map<String, dynamic>;
    if (release['hash'] == stableHash) {
      final dart = (release['dart_sdk_version'] as String).split(' ').first;
      return (release['version'] as String, dart);
    }
  }
  throw StateError('Stable release $stableHash not found in manifest');
}
