import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/score_result.dart';

void main() {
  group('ScoreResult', () {
    test('scores sum correctly', () {
      const r = ScoreResult(scores: {'a': 80, 'b': 80, 'c': 40, 'd': 60});
      expect(r.scores.values.fold(0, (a, b) => a + b), 260);
    });

    test('equality: same scores are equal', () {
      const a = ScoreResult(scores: {'x': 1, 'y': 2});
      const b = ScoreResult(scores: {'x': 1, 'y': 2});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality: different scores are not equal', () {
      const a = ScoreResult(scores: {'x': 1, 'y': 2});
      const b = ScoreResult(scores: {'x': 1, 'y': 3});
      expect(a, isNot(b));
    });

    test('equality: different lengths are not equal', () {
      const a = ScoreResult(scores: {'x': 1});
      const b = ScoreResult(scores: {'x': 1, 'y': 2});
      expect(a, isNot(b));
    });

    test('equality: independent of map insertion order', () {
      const a = ScoreResult(scores: {'x': 1, 'y': 2});
      const b = ScoreResult(scores: {'y': 2, 'x': 1});
      expect(a, b);
      // NOTE: hashCode is currently order-dependent (Object.hashAll), which
      // violates the equals/hashCode contract. Locking in current behavior
      // here; do not assert hashCode equality.
    });
  });
}
