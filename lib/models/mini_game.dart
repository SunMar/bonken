import 'package:flutter/widgets.dart';

import 'double_matrix.dart';
import 'input_descriptor.dart';
import 'player.dart';
import 'score_result.dart';

/// Number of players in a Bonken game (always 4).
const int playerCount = 4;

/// Position of [player] in the doubling turn order for a round chosen by
/// [chooserIndex]: `0` is the first to double (the player to the left of
/// the chooser, i.e. `(chooserIndex + 1) % 4`) and `3` is the chooser
/// themselves, who doubles last.
///
/// The same index drives both the input list ordering in `DoublesPicker`
/// and the chip ordering in `DoublesChips`, so they always agree.
int doublingTurnIndex(int player, int chooserIndex) =>
    (player - chooserIndex - 1 + playerCount) % playerCount;

/// The category of a mini-game.
enum GameCategory { positive, negative }

/// Avatar contents for a [MiniGame].
///
/// Dart has no native union types, so we model the "either a short text
/// label, a suit glyph, or a vector icon" choice as a sealed class with
/// three variants: [TextSymbol], [SuitSymbol] and [IconSymbol]. Sealed
/// classes give us exhaustive `switch` checking at compile time — adding
/// a fourth variant would make the renderer in `_GameSymbol` (and any
/// other consumer) fail to compile until every branch is updated, which
/// is exactly the safety net the previous `Object`-typed field plus
/// runtime `assert` was lacking.
sealed class GameSymbol {
  const GameSymbol();
}

/// A short text label rendered as bold characters (e.g. `'SA'`, `'7/13'`).
class TextSymbol extends GameSymbol {
  const TextSymbol(this.text);
  final String text;
}

/// A card-suit glyph (♠ ♥ ♦ ♣) rendered with the bundled `DejaVu
/// Sans` font at regular weight — the same font the icon SVGs use, so
/// on-screen suits and launcher icons match. Bundling the font also
/// stops Android from substituting colored emoji for these codepoints.
class SuitSymbol extends GameSymbol {
  const SuitSymbol(this.text);
  final String text;
}

/// A vector icon rendered at roughly the cap height of adjacent text.
/// Icons come from `Symbols` (Material Symbols).
class IconSymbol extends GameSymbol {
  const IconSymbol(this.icon);
  final IconData icon;
}

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
    required this.symbol,
    required this.category,
    required this.pointsPerUnit,
    required this.totalPoints,
  });

  /// Unique identifier used in code (English, camelCase).
  final String id;

  /// Display name shown in the UI (Dutch).
  final String name;

  /// Avatar contents shown for this game in the UI: a [TextSymbol] (short
  /// bold label), a [SuitSymbol] (♠ ♥ ♦ ♣ in DejaVu Sans), or an
  /// [IconSymbol] (vector glyph). The [GameSymbol] sealed class enforces
  /// this union at compile time.
  final GameSymbol symbol;

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
  /// Keys are player UUIDs (matching [players]). Values are counts per player.
  /// For trick-based games this is the number of tricks won.
  /// For card-based games this is the number of scoring cards won.
  Map<String, int> rawCounts(Map<String, dynamic> input, List<Player> players);

  /// Describes what input fields this game requires.
  /// The UI uses this to render the correct form without knowing concrete types.
  InputDescriptor get inputDescriptor;

  // ---------------------------------------------------------------------------
  // Shared helpers for subclasses
  // ---------------------------------------------------------------------------

  /// Extracts a per-player count map from [input] using the given [key].
  ///
  /// Covers the common case where [input[key]] is a `Map<String, int>` keyed
  /// by player UUID. Players absent from the map default to 0.
  @protected
  Map<String, int> countsForKey(
    String key,
    Map<String, dynamic> input,
    List<Player> players,
  ) {
    final map = (input[key] as Map).cast<String, int>();
    return {for (final p in players) p.id: map[p.id] ?? 0};
  }

  // ---------------------------------------------------------------------------
  // Shared scoring engine
  // ---------------------------------------------------------------------------

  ScoreResult calculateScores({
    required Map<String, dynamic> input,
    required DoubleMatrix doubles,
    required List<Player> players,
  }) {
    final counts = rawCounts(input, players);
    final effective = <String, int>{};
    for (final pa in players) {
      int e = counts[pa.id] ?? 0;
      for (final pb in players) {
        if (pa.id == pb.id) continue;
        final m = doubles.multiplierFor(pa.id, pb.id);
        if (m > 0) e += ((counts[pa.id] ?? 0) - (counts[pb.id] ?? 0)) * m;
      }
      effective[pa.id] = e == 0 ? 0 : e * pointsPerUnit;
    }
    return ScoreResult(scores: effective);
  }
}
