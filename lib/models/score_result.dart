/// The score outcome produced after calculating a single mini-game round.
///
/// Keys are player indices (0–3). Values are the points for that round
/// (positive = gained, negative = lost).
class ScoreResult {
  const ScoreResult({required this.scores});

  /// Maps player index → score delta for this round.
  final Map<int, int> scores;

  /// Sanity-check: sum of all scores equals the expected game total.
  bool validateTotal(int expectedTotal) =>
      scores.values.fold(0, (a, b) => a + b) == expectedTotal;

  @override
  bool operator ==(Object other) =>
      other is ScoreResult &&
      scores.length == other.scores.length &&
      scores.entries.every((e) => other.scores[e.key] == e.value);

  @override
  int get hashCode =>
      Object.hashAll(scores.entries.map((e) => Object.hash(e.key, e.value)));
}
