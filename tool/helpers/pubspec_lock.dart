// Pure parsing logic for pubspec.lock, extracted so it can be unit-tested
// with fixture data without any file I/O.

import 'package:yaml/yaml.dart';

/// Parses the resolved name → version map from a pubspec.lock YAML string.
///
/// Only packages with a non-null string `version` field are included. SDK
/// pseudo-packages (`flutter`, `dart`) that have no version field are omitted.
Map<String, String> parseLockfileVersions(String lockContent) {
  final yaml = loadYaml(lockContent);
  if (yaml is! Map) return {};
  final packages = yaml['packages'];
  if (packages is! Map) return {};
  final result = <String, String>{};
  for (final entry in packages.entries) {
    final meta = entry.value;
    if (meta is Map) {
      final version = meta['version'];
      if (version is String) {
        result[entry.key as String] = version;
      }
    }
  }
  return result;
}
