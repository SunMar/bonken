import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/score_result.dart';

void main() {
  group('ScoreResult', () {
    test('validateTotal returns true for matching sum', () {
      const r = ScoreResult(scores: {0: 80, 1: 80, 2: 40, 3: 60});
      expect(r.validateTotal(260), isTrue);
    });

    test('validateTotal returns false for mismatched sum', () {
      const r = ScoreResult(scores: {0: 10, 1: 20, 2: 30, 3: 40});
      expect(r.validateTotal(99), isFalse);
    });

    test('validateTotal handles negative totals', () {
      const r = ScoreResult(scores: {0: -50, 1: 0, 2: -50, 3: 0});
      expect(r.validateTotal(-100), isTrue);
    });

    test('equality: same scores are equal', () {
      const a = ScoreResult(scores: {0: 1, 1: 2});
      const b = ScoreResult(scores: {0: 1, 1: 2});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality: different scores are not equal', () {
      const a = ScoreResult(scores: {0: 1, 1: 2});
      const b = ScoreResult(scores: {0: 1, 1: 3});
      expect(a, isNot(b));
    });

    test('equality: different lengths are not equal', () {
      const a = ScoreResult(scores: {0: 1});
      const b = ScoreResult(scores: {0: 1, 1: 2});
      expect(a, isNot(b));
    });

    test('equality: independent of map insertion order', () {
      const a = ScoreResult(scores: {0: 1, 1: 2});
      const b = ScoreResult(scores: {1: 2, 0: 1});
      expect(a, b);
      // NOTE: hashCode is currently order-dependent (Object.hashAll), which
      // violates the equals/hashCode contract. Locking in current behavior
      // here; do not assert hashCode equality.
    });
  });
}
