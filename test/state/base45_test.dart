import 'dart:convert';

import 'package:bonken/state/base45.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Base45 RFC 9285 vectors', () {
    // The worked examples from https://www.rfc-editor.org/rfc/rfc9285.
    const vectors = {
      'AB': 'BB8',
      'Hello!!': '%69 VD92EX0',
      'base-45': 'UJCLQE7W581',
      'ietf!': 'QED8WEX0',
    };

    vectors.forEach((plain, encoded) {
      test('"$plain" encodes to "$encoded"', () {
        expect(Base45.encode(utf8.encode(plain)), encoded);
      });
      test('"$encoded" decodes back to "$plain"', () {
        expect(utf8.decode(Base45.decode(encoded)), plain);
      });
    });
  });

  group('Base45 round-trip', () {
    for (final bytes in <List<int>>[
      [],
      [0],
      [255],
      [0, 0],
      [255, 255],
      [1, 2, 3],
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      [for (var b = 0; b < 256; b++) b],
    ]) {
      test('${bytes.length} bytes survive encode→decode', () {
        expect(Base45.decode(Base45.encode(bytes)), bytes);
      });
    }

    test('an empty input encodes to an empty string', () {
      expect(Base45.encode(const []), '');
      expect(Base45.decode(''), isEmpty);
    });

    test('every encoded character is in the QR alphanumeric set', () {
      // The whole point of base45: output stays within the characters the `qr`
      // package can pack into its denser alphanumeric mode.
      const alphanumeric = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';
      final encoded = Base45.encode([for (var b = 0; b < 256; b++) b]);
      for (final char in encoded.split('')) {
        expect(
          alphanumeric.contains(char),
          isTrue,
          reason: 'stray char "$char"',
        );
      }
    });
  });

  group('Base45 decode rejects malformed input', () {
    test('a character outside the alphabet throws', () {
      expect(() => Base45.decode('ab'), throwsFormatException); // lowercase
      expect(() => Base45.decode('A!'), throwsFormatException);
    });

    test('a length that leaves one dangling character throws', () {
      expect(() => Base45.decode('A'), throwsFormatException); // 1 char
      expect(() => Base45.decode('BB8A'), throwsFormatException); // 4 chars
    });

    test('a triple whose value exceeds 0xFFFF throws', () {
      expect(() => Base45.decode(':::'), throwsFormatException); // 91124
    });

    test('a trailing pair whose value exceeds 0xFF throws', () {
      expect(() => Base45.decode('::'), throwsFormatException); // 2024
    });
  });
}
