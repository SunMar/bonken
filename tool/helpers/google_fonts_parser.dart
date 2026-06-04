// Pure parsing logic extracted from tool/update_fonts.dart so it can be
// unit-tested with fixture data without any file I/O or network access.
//
// The google_fonts package stores per-font download hashes in Dart source files
// (`lib/src/google_fonts_parts/part_*.dart`). Each font has a static method
// that lists GoogleFontsFile records with a 64-char hex hash and a byte size.
// This module extracts those hashes by parsing the source text.

/// Describes one weight+style variant of a bundled font.
typedef FontVariant = ({
  FontWeight fontWeight,
  FontStyle fontStyle,
  String hash,
});

/// Simplified weight enum matching the google_fonts source weight constants.
enum FontWeight { w100, w200, w300, w400, w500, w600, w700, w800, w900 }

/// Simplified style enum matching the google_fonts source style constants.
enum FontStyle { normal, italic }

/// Parses all [FontVariant]s from a google_fonts part_*.dart source string for
/// the font [fontName] (e.g. `'roboto'` or `'arimo'`).
///
/// The method signature in the source is:
///   `static TextStyle <fontName>(`
/// followed by a block that maps `GoogleFontsVariant(fontWeight: …, fontStyle: …)`
/// to `GoogleFontsFile('<64-hex-hash>', …)`.
///
/// Throws [FormatException] when the block cannot be found or no hashes are
/// parsed — a layout change in the google_fonts source would show up here.
List<FontVariant> parseFontVariants(String dartSource, String fontName) {
  // Locate the static method block for this font.
  final methodPattern = RegExp(
    r'static TextStyle ' + RegExp.escape(fontName) + r'\(',
    caseSensitive: false,
  );
  final methodMatch = methodPattern.firstMatch(dartSource);
  if (methodMatch == null) {
    throw FormatException(
      "Could not find 'static TextStyle $fontName(' in source",
    );
  }

  // Find the closing brace of the fonts map (`fontFamily: '<Name>'` marks end).
  final afterMethod = dartSource.substring(methodMatch.start);
  final endPattern = RegExp(r"fontFamily:\s*'" + _capitalize(fontName) + r"'");
  final endMatch = endPattern.firstMatch(afterMethod);
  final block = endMatch != null
      ? afterMethod.substring(0, endMatch.start)
      : afterMethod;

  // Parse variant + hash pairs.
  final variantPattern = RegExp(
    r'GoogleFontsVariant\(\s*'
    r'fontWeight:\s*FontWeight\.(\w+),\s*'
    r'fontStyle:\s*FontStyle\.(\w+),?\s*'
    r'\)[^:]*:\s*GoogleFontsFile\(\s*'
    r"'([0-9a-f]{64})'",
    dotAll: true,
  );

  final results = <FontVariant>[];
  for (final m in variantPattern.allMatches(block)) {
    final weight = _parseWeight(m.group(1)!);
    final style = _parseStyle(m.group(2)!);
    final hash = m.group(3)!;
    results.add((fontWeight: weight, fontStyle: style, hash: hash));
  }

  if (results.isEmpty) {
    throw FormatException(
      'No hashes found in $fontName block — layout change?',
    );
  }
  return results;
}

/// Returns the hash for [weight] + [FontStyle.normal] from [variants], or
/// throws [StateError] if not found.
String hashForWeight(List<FontVariant> variants, FontWeight weight) {
  final match = variants.where(
    (v) => v.fontWeight == weight && v.fontStyle == FontStyle.normal,
  );
  if (match.isEmpty) {
    throw StateError('No normal-style hash found for weight $weight');
  }
  return match.first.hash;
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

FontWeight _parseWeight(String name) {
  for (final w in FontWeight.values) {
    if (w.name == name) return w;
  }
  throw FormatException('Unknown FontWeight: $name');
}

FontStyle _parseStyle(String name) {
  for (final s in FontStyle.values) {
    if (s.name == name) return s;
  }
  throw FormatException('Unknown FontStyle: $name');
}
