import 'package:bonken/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four canonical test players (A, B, C, D) in seat order.
///
/// Built fresh on every call so each test file gets its own stable, file-local
/// UUIDs from a single shared fixture — the scoring tests no longer each
/// re-declare the same four `Player(name: …)` lines.
List<Player> fourTestPlayers() => [
  Player(name: 'A'),
  Player(name: 'B'),
  Player(name: 'C'),
  Player(name: 'D'),
];

/// Asserts that every score in [scores] sums to [expectedTotal] — the per-game
/// `Σ scores == totalPoints` invariant that holds regardless of doubling
/// (ARCHITECTURE.md §6).
void expectTotal(Map<String, int> scores, int expectedTotal) {
  final sum = scores.values.fold(0, (a, b) => a + b);
  expect(
    sum,
    equals(expectedTotal),
    reason:
        'Score total $sum ≠ expected $expectedTotal\n'
        'Scores: $scores',
  );
}
