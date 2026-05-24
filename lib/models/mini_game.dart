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

/// Base class for all 13 Bonken mini-games. Concrete games don't extend this
/// directly — they extend one of the shape bases below ([CountsMiniGame],
/// [SinglePlayerMiniGame], [DualPlayerMiniGame]), which implement [rawCounts],
/// [inputDescriptor] and the storage round-trip for their input shape; a leaf
/// game only supplies [id], [name], [symbol], [category], [pointsPerUnit],
/// [totalPoints] + the shape's human-facing fields.
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

  /// Serializes the in-memory [input] to the uniform persisted form: a
  /// positional list of per-player count maps (see ARCHITECTURE.md §9). Counts
  /// and single-player games yield one element; dual-player games yield two
  /// (ordered) elements. The inverse is [countsToInput].
  List<Map<String, int>> inputToCounts(Map<String, dynamic> input);

  /// Rebuilds the in-memory input map from a persisted [counts] list — the
  /// inverse of [inputToCounts]. Called when loading/restoring a saved round.
  Map<String, dynamic> countsToInput(List<Map<String, int>> counts);

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

// =============================================================================
// Intermediate bases — one per input shape, mirroring the sealed
// InputDescriptor hierarchy. Each owns its canonical input key(s), its
// rawCounts strategy, its descriptor, and the storage round-trip
// (inputToCounts / countsToInput). Leaf games only declare id/name/symbol/
// points + the human-facing bits (total/unitLabel or prompt(s)).
// =============================================================================

/// Returns the single player id in a count map (the entry with count ≥ 1), or
/// `null` when the map is empty. Used to invert a single-pick storage element
/// back into a `'player'`-style input value.
String? _soleKey(Map<String, int> counts) {
  for (final e in counts.entries) {
    if (e.value >= 1) return e.key;
  }
  return null;
}

/// Games where each of the 4 players enters a count (tricks / scoring cards
/// won) and the four counts sum to [total]. Canonical input key: `'counts'`,
/// a `{playerId: count}` map.
abstract class CountsMiniGame extends MiniGame {
  const CountsMiniGame({
    required super.id,
    required super.name,
    required super.symbol,
    required super.category,
    required super.pointsPerUnit,
    required super.totalPoints,
    required this.total,
    required this.unitLabel,
  });

  /// Required sum of the four per-player counts.
  final int total;

  /// Dutch unit shown in the counts form (e.g. 'slagen', 'harten').
  final String unitLabel;

  static const _inputKey = 'counts';

  @override
  Map<String, int> rawCounts(Map<String, dynamic> input, List<Player> players) {
    final map = (input[_inputKey] as Map).cast<String, int>();
    return {for (final p in players) p.id: map[p.id] ?? 0};
  }

  @override
  InputDescriptor get inputDescriptor => CountsInputDescriptor(
    inputKey: _inputKey,
    total: total,
    unitLabel: unitLabel,
  );

  @override
  List<Map<String, int>> inputToCounts(Map<String, dynamic> input) => [
    (input[_inputKey] as Map?)?.cast<String, int>() ?? const <String, int>{},
  ];

  @override
  Map<String, dynamic> countsToInput(List<Map<String, int>> counts) => {
    _inputKey: counts.isEmpty ? <String, int>{} : counts.first,
  };
}

/// Games where exactly one player is selected (the player who won that
/// trick/card — and is therefore penalised in the negative games). Canonical
/// input key: `'player'`, a single player id (or `null`).
abstract class SinglePlayerMiniGame extends MiniGame {
  const SinglePlayerMiniGame({
    required super.id,
    required super.name,
    required super.symbol,
    required super.category,
    required super.pointsPerUnit,
    required super.totalPoints,
    required this.prompt,
  });

  /// Question shown above the player selector (Dutch).
  final String prompt;

  static const _inputKey = 'player';

  @override
  Map<String, int> rawCounts(Map<String, dynamic> input, List<Player> players) {
    final selected = input[_inputKey] as String?;
    return {for (final p in players) p.id: selected == p.id ? 1 : 0};
  }

  @override
  InputDescriptor get inputDescriptor =>
      SinglePlayerInputDescriptor(inputKey: _inputKey, prompt: prompt);

  @override
  List<Map<String, int>> inputToCounts(Map<String, dynamic> input) {
    final selected = input[_inputKey] as String?;
    return [
      selected == null ? <String, int>{} : {selected: 1},
    ];
  }

  @override
  Map<String, dynamic> countsToInput(List<Map<String, int>> counts) => {
    _inputKey: _soleKey(counts.isEmpty ? const {} : counts.first),
  };
}

/// Games with two independent single-player picks (7e / 13e). Canonical input
/// keys: `'player1'` (first sub-result) and `'player2'` (second); the stored
/// counts list is positional, so the two picks never blur together.
abstract class DualPlayerMiniGame extends MiniGame {
  const DualPlayerMiniGame({
    required super.id,
    required super.name,
    required super.symbol,
    required super.category,
    required super.pointsPerUnit,
    required super.totalPoints,
    required this.prompt1,
    required this.prompt2,
  });

  final String prompt1;
  final String prompt2;

  static const _key1 = 'player1';
  static const _key2 = 'player2';

  @override
  Map<String, int> rawCounts(Map<String, dynamic> input, List<Player> players) {
    final p1 = input[_key1] as String?;
    final p2 = input[_key2] as String?;
    return {
      for (final p in players)
        p.id: (p1 == p.id ? 1 : 0) + (p2 == p.id ? 1 : 0),
    };
  }

  @override
  InputDescriptor get inputDescriptor => DualPlayerInputDescriptor(
    inputKey1: _key1,
    prompt1: prompt1,
    inputKey2: _key2,
    prompt2: prompt2,
  );

  @override
  List<Map<String, int>> inputToCounts(Map<String, dynamic> input) {
    final p1 = input[_key1] as String?;
    final p2 = input[_key2] as String?;
    return [
      p1 == null ? <String, int>{} : {p1: 1},
      p2 == null ? <String, int>{} : {p2: 1},
    ];
  }

  @override
  Map<String, dynamic> countsToInput(List<Map<String, int>> counts) => {
    _key1: _soleKey(counts.isNotEmpty ? counts[0] : const {}),
    _key2: _soleKey(counts.length > 1 ? counts[1] : const {}),
  };
}
