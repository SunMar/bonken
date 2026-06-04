// Pure functions for format-preserving reads and edits of pubspec.yaml (or any
// YAML document).
//
// All functions take the document as a string and return the modified string so
// callers handle file I/O themselves and tests can work without touching disk.
// Reads use `package:yaml` (loadYaml); writes use `package:yaml_edit`
// (YamlEditor), which applies surgical key-path edits and preserves all
// surrounding comments and formatting by design.

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Returns the string value at [keyPath] in [yamlContent], or `null` when the
/// path is absent or the value is not a string.
String? readYamlString(String yamlContent, List<Object> keyPath) {
  dynamic node = loadYaml(yamlContent);
  for (final key in keyPath) {
    if (node is! Map) return null;
    node = node[key];
  }
  return node is String ? node : null;
}

/// Returns every string in the YAML sequence at [keyPath], or an empty list
/// when the path is absent or not a sequence.
List<String> readYamlStringList(String yamlContent, List<Object> keyPath) {
  final node = _resolveNode(loadYaml(yamlContent), keyPath);
  if (node is! List) return const [];
  return [
    for (final v in node)
      if (v is String) v,
  ];
}

/// Sets the scalar at [keyPath] to [newValue], preserving all surrounding
/// comments and formatting.
String setYamlValue(String yamlContent, List<Object> keyPath, Object newValue) {
  final editor = YamlEditor(yamlContent);
  editor.update(keyPath, newValue);
  return editor.toString();
}

/// Replaces the first list entry at [listKeyPath] for which [predicate]
/// returns true with [newEntry], preserving formatting.
///
/// Returns the unmodified [yamlContent] when no entry matches.
String replaceYamlListEntry(
  String yamlContent,
  List<Object> listKeyPath,
  bool Function(String) predicate,
  String newEntry,
) {
  final node = _resolveNode(loadYaml(yamlContent), listKeyPath);
  if (node is! List) return yamlContent;
  for (var i = 0; i < node.length; i++) {
    if (node[i] is String && predicate(node[i] as String)) {
      final editor = YamlEditor(yamlContent);
      editor.update([...listKeyPath, i], newEntry);
      return editor.toString();
    }
  }
  return yamlContent;
}

dynamic _resolveNode(dynamic root, List<Object> keyPath) {
  dynamic node = root;
  for (final key in keyPath) {
    if (node is! Map) return null;
    node = node[key];
  }
  return node;
}
