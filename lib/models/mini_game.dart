import 'double_matrix.dart';
import 'input_descriptor.dart';
import 'score_result.dart';

/// Number of players in a Bonken game (always 4).
const int playerCount = 4;

/// The category of a mini-game.
enum GameCategory { positive, negative }

/// Base class for all 13 Bonken mini-games.
///
/// Subclasses only need to:
///   1. Supply [id], [name], [category], and [pointsPerUnit].
///   2. Override [rawCounts] to derive a per-player integer count from the
///      game-specific [input] map.
///
/// The shared [calculateScores] method handles all doubling/redoubling logic
/// and converts effective counts to points.
///
/// ## Scoring algorithm (doubles)
///
/// For player i:
///   effectiveCount(i) = rawCount(i)
///                     + Σ_j [ (rawCount(i) - rawCount(j)) × multiplier(i,j) ]
///
/// Then: score(i) = effectiveCount(i) × pointsPerUnit
///
/// When no pairs are doubled, effectiveCount equals rawCount and the classic
/// straight score applies.  The sum of all scores always equals
/// Σ rawCounts × pointsPerUnit regardless of doubling.
abstract class MiniGame {
  const MiniGame({
    required this.id,
    required this.name,
    required this.category,
    required this.pointsPerUnit,
    required this.totalPoints,
  });

  /// Unique identifier used in code (English, camelCase).
  final String id;

  /// Display name shown in the UI (Dutch).
  final String name;

  final GameCategory category;

  /// Points awarded (or lost) per unit counted.
  /// Positive for positive games (+20), negative for negative games.
  final int pointsPerUnit;

  /// The fixed sum of all player scores for this game (sanity check).
  final int totalPoints;

  // ---------------------------------------------------------------------------
  // Subclass contract
  // ---------------------------------------------------------------------------

  /// Derives a raw integer count for each player from game-specific [input].
  ///
  /// The list must have exactly 4 entries (index = player index).
  /// For trick-based games this is the number of tricks won.
  /// For card-based games this is the number of scoring cards won.
  List<int> rawCounts(Map<String, dynamic> input);

  /// Describes what input fields this game requires.
  /// The UI uses this to render the correct form without knowing concrete types.
  InputDescriptor get inputDescriptor;

  // ---------------------------------------------------------------------------
  // Shared scoring engine
  // ---------------------------------------------------------------------------

  ScoreResult calculateScores({
    required Map<String, dynamic> input,
    required DoubleMatrix doubles,
  }) {
    final counts = rawCounts(input);
    assert(counts.length == playerCount);

    final effective = List<int>.generate(playerCount, (i) {
      int e = counts[i];
      for (int j = 0; j < playerCount; j++) {
        if (i == j) continue;
        final m = doubles.multiplierFor(i, j);
        if (m > 0) e += (counts[i] - counts[j]) * m;
      }
      return e;
    });

    return ScoreResult(
      scores: {
        for (int i = 0; i < playerCount; i++)
          i: effective[i] == 0 ? 0 : effective[i] * pointsPerUnit,
      },
    );
  }
}
