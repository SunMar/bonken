import 'package:bonken/models/double_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

import '_double_matrix_helpers.dart';

// Short string IDs used as stand-ins for player UUIDs.
const a = 'player-a';
const b = 'player-b';
const c = 'player-c';
const d = 'player-d';

void main() {
  group('empty matrix (default const constructor)', () {
    test('returns a matrix with no doubles', () {
      const m = DoubleMatrix();
      expect(m.hasAnyDouble, isFalse);
      for (final x in [a, b, c, d]) {
        for (final y in [a, b, c, d]) {
          if (x == y) continue;
          expect(m.stateFor(x, y), DoubleState.none);
          expect(m.multiplierFor(x, y), 0);
          expect(m.initiatorFor(x, y), isNull);
        }
      }
    });
  });

  group('canonicalisation', () {
    test('stateFor is symmetric (a,b) == (b,a)', () {
      final m = const DoubleMatrix().withState(b, d, DoubleState.doubled);
      expect(m.stateFor(b, d), DoubleState.doubled);
      expect(m.stateFor(d, b), DoubleState.doubled);
    });

    test('multiplierFor is symmetric', () {
      final m = const DoubleMatrix().withState(a, c, DoubleState.redoubled);
      expect(m.multiplierFor(a, c), 2);
      expect(m.multiplierFor(c, a), 2);
    });

    test('initiatorFor is symmetric', () {
      final m = const DoubleMatrix().withPair(
        c,
        a,
        DoubleState.doubled,
        initiator: c,
      );
      expect(m.initiatorFor(a, c), c);
      expect(m.initiatorFor(c, a), c);
    });
  });

  group('withPair / withState', () {
    test('multipliers map to expected values', () {
      final m = const DoubleMatrix()
          .withState(a, b, DoubleState.doubled)
          .withState(a, c, DoubleState.redoubled);
      expect(m.multiplierFor(a, b), 1);
      expect(m.multiplierFor(a, c), 2);
      expect(m.multiplierFor(a, d), 0);
    });

    test('withState sets initiator to first arg', () {
      final m = const DoubleMatrix().withState(c, b, DoubleState.doubled);
      expect(m.initiatorFor(b, c), c);
    });

    test('withPair preserves explicit initiator', () {
      final m = const DoubleMatrix().withPair(
        a,
        d,
        DoubleState.doubled,
        initiator: d,
      );
      expect(m.initiatorFor(a, d), d);
    });

    test('clearing a pair (state none) removes state and initiator', () {
      final m = const DoubleMatrix()
          .withState(b, c, DoubleState.doubled)
          .withPair(b, c, DoubleState.none);
      expect(m.stateFor(b, c), DoubleState.none);
      expect(m.initiatorFor(b, c), isNull);
      expect(m.hasAnyDouble, isFalse);
    });

    test('updating preserves other pairs', () {
      final m = const DoubleMatrix()
          .withState(a, b, DoubleState.doubled)
          .withState(c, d, DoubleState.redoubled);
      final updated = m.withState(a, b, DoubleState.redoubled);
      expect(updated.stateFor(a, b), DoubleState.redoubled);
      expect(updated.stateFor(c, d), DoubleState.redoubled);
    });

    test('immutability: original matrix is not mutated', () {
      const original = DoubleMatrix();
      original.withState(a, b, DoubleState.doubled);
      expect(original.hasAnyDouble, isFalse);
    });
  });

  group('hasAnyDouble', () {
    test('true after a single double', () {
      final m = const DoubleMatrix().withState(a, b, DoubleState.doubled);
      expect(m.hasAnyDouble, isTrue);
    });

    test('false after clearing all doubles', () {
      final m = const DoubleMatrix()
          .withState(a, b, DoubleState.doubled)
          .withPair(a, b, DoubleState.none);
      expect(m.hasAnyDouble, isFalse);
    });
  });

  group('equality', () {
    test('empty matrices are equal', () {
      expect(const DoubleMatrix(), const DoubleMatrix());
      expect(const DoubleMatrix().hashCode, const DoubleMatrix().hashCode);
    });

    test('matrices with same pairs/initiators are equal', () {
      final x = const DoubleMatrix()
          .withState(a, b, DoubleState.doubled)
          .withState(c, d, DoubleState.redoubled);
      final y = const DoubleMatrix()
          .withState(c, d, DoubleState.redoubled)
          .withState(a, b, DoubleState.doubled);
      expect(x, y);
      expect(x.hashCode, y.hashCode);
    });

    test('matrices with different states are not equal', () {
      final x = const DoubleMatrix().withState(a, b, DoubleState.doubled);
      final y = const DoubleMatrix().withState(a, b, DoubleState.redoubled);
      expect(x, isNot(y));
    });

    test('matrices with different initiators are not equal', () {
      final x = const DoubleMatrix().withPair(
        a,
        b,
        DoubleState.doubled,
        initiator: a,
      );
      final y = const DoubleMatrix().withPair(
        a,
        b,
        DoubleState.doubled,
        initiator: b,
      );
      expect(x, isNot(y));
    });
  });

  group('JSON serialization', () {
    test('empty matrix roundtrips', () {
      const m = DoubleMatrix();
      final back = DoubleMatrix.fromJson(m.toJson());
      expect(back, m);
    });

    test('complex matrix roundtrips with state and initiators', () {
      final m = const DoubleMatrix()
          .withPair(a, b, DoubleState.doubled, initiator: b)
          .withPair(a, c, DoubleState.redoubled, initiator: a)
          .withPair(c, d, DoubleState.doubled, initiator: d);
      final back = DoubleMatrix.fromJson(m.toJson());
      expect(back, m);
      expect(back.stateFor(a, b), DoubleState.doubled);
      expect(back.initiatorFor(a, b), b);
      expect(back.stateFor(a, c), DoubleState.redoubled);
      expect(back.initiatorFor(a, c), a);
      expect(back.stateFor(c, d), DoubleState.doubled);
      expect(back.initiatorFor(c, d), d);
    });

    test('fromJson handles empty object (no active pairs)', () {
      final m = DoubleMatrix.fromJson(<String, dynamic>{});
      expect(m.hasAnyDouble, isFalse);
    });

    test('fromJson rejects a pair key with no comma', () {
      expect(
        () => DoubleMatrix.fromJson({
          'nocomma': {'state': 'doubled', 'initiator': a},
        }),
        throwsFormatException,
      );
    });
  });
}
