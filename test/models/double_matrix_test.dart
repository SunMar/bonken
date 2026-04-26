import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/double_matrix.dart';

void main() {
  group('DoubleMatrix.empty', () {
    test('returns a matrix with no doubles', () {
      final m = DoubleMatrix.empty();
      expect(m.hasAnyDouble, isFalse);
      for (int a = 0; a < 4; a++) {
        for (int b = a + 1; b < 4; b++) {
          expect(m.stateFor(a, b), DoubleState.none);
          expect(m.multiplierFor(a, b), 0);
          expect(m.initiatorFor(a, b), isNull);
        }
      }
    });
  });

  group('canonicalisation', () {
    test('stateFor is symmetric (a,b) == (b,a)', () {
      final m = DoubleMatrix.empty().withState(1, 3, DoubleState.doubled);
      expect(m.stateFor(1, 3), DoubleState.doubled);
      expect(m.stateFor(3, 1), DoubleState.doubled);
    });

    test('multiplierFor is symmetric', () {
      final m = DoubleMatrix.empty().withState(0, 2, DoubleState.redoubled);
      expect(m.multiplierFor(0, 2), 2);
      expect(m.multiplierFor(2, 0), 2);
    });

    test('initiatorFor is symmetric', () {
      final m = DoubleMatrix.empty().withPair(
        2,
        0,
        DoubleState.doubled,
        initiator: 2,
      );
      expect(m.initiatorFor(0, 2), 2);
      expect(m.initiatorFor(2, 0), 2);
    });
  });

  group('withPair / withState', () {
    test('multipliers map to expected values', () {
      final m = DoubleMatrix.empty()
          .withState(0, 1, DoubleState.doubled)
          .withState(0, 2, DoubleState.redoubled);
      expect(m.multiplierFor(0, 1), 1);
      expect(m.multiplierFor(0, 2), 2);
      expect(m.multiplierFor(0, 3), 0);
    });

    test('withState sets initiator to first arg', () {
      final m = DoubleMatrix.empty().withState(2, 1, DoubleState.doubled);
      expect(m.initiatorFor(1, 2), 2);
    });

    test('withPair preserves explicit initiator', () {
      final m = DoubleMatrix.empty().withPair(
        0,
        3,
        DoubleState.doubled,
        initiator: 3,
      );
      expect(m.initiatorFor(0, 3), 3);
    });

    test('clearing a pair (state none) removes state and initiator', () {
      final m = DoubleMatrix.empty()
          .withState(1, 2, DoubleState.doubled)
          .withPair(1, 2, DoubleState.none);
      expect(m.stateFor(1, 2), DoubleState.none);
      expect(m.initiatorFor(1, 2), isNull);
      expect(m.hasAnyDouble, isFalse);
    });

    test('updating preserves other pairs', () {
      final m = DoubleMatrix.empty()
          .withState(0, 1, DoubleState.doubled)
          .withState(2, 3, DoubleState.redoubled);
      final updated = m.withState(0, 1, DoubleState.redoubled);
      expect(updated.stateFor(0, 1), DoubleState.redoubled);
      expect(updated.stateFor(2, 3), DoubleState.redoubled);
    });

    test('immutability: original matrix is not mutated', () {
      final original = DoubleMatrix.empty();
      original.withState(0, 1, DoubleState.doubled);
      expect(original.hasAnyDouble, isFalse);
    });
  });

  group('hasAnyDouble', () {
    test('true after a single double', () {
      final m = DoubleMatrix.empty().withState(0, 1, DoubleState.doubled);
      expect(m.hasAnyDouble, isTrue);
    });

    test('false after clearing all doubles', () {
      final m = DoubleMatrix.empty()
          .withState(0, 1, DoubleState.doubled)
          .withPair(0, 1, DoubleState.none);
      expect(m.hasAnyDouble, isFalse);
    });
  });

  group('equality', () {
    test('empty matrices are equal', () {
      expect(DoubleMatrix.empty(), DoubleMatrix.empty());
      expect(DoubleMatrix.empty().hashCode, DoubleMatrix.empty().hashCode);
    });

    test('matrices with same pairs/initiators are equal', () {
      final a = DoubleMatrix.empty()
          .withState(0, 1, DoubleState.doubled)
          .withState(2, 3, DoubleState.redoubled);
      final b = DoubleMatrix.empty()
          .withState(2, 3, DoubleState.redoubled)
          .withState(0, 1, DoubleState.doubled);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('matrices with different states are not equal', () {
      final a = DoubleMatrix.empty().withState(0, 1, DoubleState.doubled);
      final b = DoubleMatrix.empty().withState(0, 1, DoubleState.redoubled);
      expect(a, isNot(b));
    });

    test('matrices with different initiators are not equal', () {
      final a = DoubleMatrix.empty().withPair(
        0,
        1,
        DoubleState.doubled,
        initiator: 0,
      );
      final b = DoubleMatrix.empty().withPair(
        0,
        1,
        DoubleState.doubled,
        initiator: 1,
      );
      expect(a, isNot(b));
    });
  });

  group('JSON serialization', () {
    test('empty matrix roundtrips', () {
      final m = DoubleMatrix.empty();
      final back = DoubleMatrix.fromJson(m.toJson());
      expect(back, m);
    });

    test('complex matrix roundtrips with state and initiators', () {
      final m = DoubleMatrix.empty()
          .withPair(0, 1, DoubleState.doubled, initiator: 1)
          .withPair(0, 2, DoubleState.redoubled, initiator: 0)
          .withPair(2, 3, DoubleState.doubled, initiator: 3);
      final back = DoubleMatrix.fromJson(m.toJson());
      expect(back, m);
      expect(back.stateFor(0, 1), DoubleState.doubled);
      expect(back.initiatorFor(0, 1), 1);
      expect(back.stateFor(0, 2), DoubleState.redoubled);
      expect(back.initiatorFor(0, 2), 0);
      expect(back.stateFor(2, 3), DoubleState.doubled);
      expect(back.initiatorFor(2, 3), 3);
    });

    test('fromJson handles missing pairs/initiators keys', () {
      final m = DoubleMatrix.fromJson(<String, dynamic>{});
      expect(m.hasAnyDouble, isFalse);
    });
  });
}
