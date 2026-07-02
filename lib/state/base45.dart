import 'dart:typed_data';

/// [RFC 9285](https://www.rfc-editor.org/rfc/rfc9285) Base45 encoding.
///
/// Base45 maps binary data onto the QR-code **alphanumeric** character set
/// (`0-9 A-Z` and ` $%*+-./:`). The `qr` package auto-selects alphanumeric mode
/// for such strings and packs it at ~5.5 bits/char, versus the 8 bits/char that
/// base64 costs (its lowercase letters force byte mode). For the same gzipped
/// payload that is a lower QR version — fewer, larger modules and an easier
/// scan. Used by [GameQrCodec]; see ARCHITECTURE.md §9.
///
/// Encoding groups the input into byte pairs: each pair (a big-endian 16-bit
/// value, 0–65535) becomes 3 characters, and a trailing odd byte (0–255)
/// becomes 2 characters — the inverse on decode.
abstract final class Base45 {
  /// The 45 symbols, indexed by their Base45 digit value.
  static const String _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

  /// Reverse lookup: code unit → digit value, for decoding.
  static final Map<int, int> _digits = {
    for (var i = 0; i < _alphabet.length; i++) _alphabet.codeUnitAt(i): i,
  };

  /// Encodes [bytes] into a Base45 string.
  static String encode(List<int> bytes) {
    final out = StringBuffer();
    var i = 0;
    for (; i + 1 < bytes.length; i += 2) {
      var value = bytes[i] * 256 + bytes[i + 1];
      out.write(_alphabet[value % 45]);
      value ~/= 45;
      out.write(_alphabet[value % 45]);
      out.write(_alphabet[value ~/ 45]);
    }
    if (i < bytes.length) {
      final value = bytes[i];
      out.write(_alphabet[value % 45]);
      out.write(_alphabet[value ~/ 45]);
    }
    return out.toString();
  }

  /// Decodes a Base45 [encoded] string back into bytes.
  ///
  /// Throws [FormatException] on any character outside the Base45 alphabet, an
  /// impossible length (`length % 3 == 1`), or a group whose value overflows its
  /// byte width. Callers decoding untrusted input (a scanned QR) catch this and
  /// report the code as invalid.
  static Uint8List decode(String encoded) {
    final digits = [for (final unit in encoded.codeUnits) _digitOf(unit)];
    final remainder = digits.length % 3;
    if (remainder == 1) {
      throw const FormatException('invalid Base45 length');
    }
    final out = <int>[];
    var i = 0;
    for (; i + 2 < digits.length; i += 3) {
      final value = digits[i] + digits[i + 1] * 45 + digits[i + 2] * 2025;
      if (value > 0xFFFF) {
        throw const FormatException('Base45 group out of range');
      }
      out.add(value ~/ 256);
      out.add(value % 256);
    }
    if (remainder == 2) {
      final value = digits[i] + digits[i + 1] * 45;
      if (value > 0xFF) {
        throw const FormatException('Base45 group out of range');
      }
      out.add(value);
    }
    return Uint8List.fromList(out);
  }

  static int _digitOf(int unit) {
    final digit = _digits[unit];
    if (digit == null) {
      throw FormatException(
        'invalid Base45 character: ${String.fromCharCode(unit)}',
      );
    }
    return digit;
  }
}
