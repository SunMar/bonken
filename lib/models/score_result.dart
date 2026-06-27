/// The score outcome produced after calculating a single mini-game round.
///
/// Keys are player UUIDs. Values are the points for that round
/// (positive = gained, negative = lost).
class ScoreResult {
  const ScoreResult({required this.scores});

  /// Maps player UUID → score delta for this round.
  final Map<String, int> scores;

  @override
  bool operator ==(Object other) =>
      other is ScoreResult &&
      scores.length == other.scores.length &&
      scores.entries.every((e) => other.scores[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    scores.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
