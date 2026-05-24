import 'player.dart';

/// Describes the input fields required by a mini-game so the UI can render
/// the correct form without knowing concrete game types.
sealed class InputDescriptor {
  const InputDescriptor();

  /// True when [input] contains no meaningful entry yet (used by both
  /// "has some input" and "has meaningful pending input" — they share
  /// identical semantics: not-empty == has at least one entered value).
  bool isEmpty(Map<String, dynamic> input);

  /// True when [input] is fully and validly filled in for this descriptor.
  bool isComplete(Map<String, dynamic> input);

  /// Initial input map used when a game is freshly selected.
  /// Input values are keyed by player UUID (not seat index).
  Map<String, dynamic> defaults(List<Player> players);
}

/// A mini-game where each of the 4 players enters a count (tricks or scoring
/// cards won). The four values must sum to [total].
///
/// Storage format: `{inputKey: {"<playerUUID>": count, ...}}`
class CountsInputDescriptor extends InputDescriptor {
  const CountsInputDescriptor({
    required this.inputKey,
    required this.total,
    required this.unitLabel,
  });

  /// Key used in the input map (canonical: 'counts', set by `CountsMiniGame`).
  final String inputKey;

  /// Required sum of all four player counts.
  final int total;

  /// Human-readable unit shown next to the count (Dutch, e.g. 'slagen').
  final String unitLabel;

  @override
  bool isEmpty(Map<String, dynamic> input) {
    final map = (input[inputKey] as Map?)?.cast<String, int>();
    if (map == null) return true;
    return map.values.fold<int>(0, (a, b) => a + b) == 0;
  }

  @override
  bool isComplete(Map<String, dynamic> input) {
    final map = (input[inputKey] as Map?)?.cast<String, int>();
    if (map == null) return false;
    return map.values.fold<int>(0, (a, b) => a + b) == total;
  }

  @override
  Map<String, dynamic> defaults(List<Player> players) => {
    inputKey: {for (final p in players) p.id: 0},
  };
}

/// A mini-game where a single player is selected (winner or loser).
///
/// Storage format: `{inputKey: "<playerUUID>" | null}`
class SinglePlayerInputDescriptor extends InputDescriptor {
  const SinglePlayerInputDescriptor({
    required this.inputKey,
    required this.prompt,
  });

  /// Key used in the input map (canonical: 'player', set by
  /// `SinglePlayerMiniGame`).
  final String inputKey;

  /// Question shown above the player selector (Dutch).
  final String prompt;

  @override
  bool isEmpty(Map<String, dynamic> input) => input[inputKey] == null;

  @override
  bool isComplete(Map<String, dynamic> input) {
    final v = input[inputKey] as String?;
    return v != null && v.isNotEmpty;
  }

  @override
  Map<String, dynamic> defaults(List<Player> players) => {inputKey: null};
}

/// A mini-game with two independent player selections (7e / 13e).
///
/// Storage format: `{inputKey1: "<playerUUID>" | null, inputKey2: "<playerUUID>" | null}`
class DualPlayerInputDescriptor extends InputDescriptor {
  const DualPlayerInputDescriptor({
    required this.inputKey1,
    required this.prompt1,
    required this.inputKey2,
    required this.prompt2,
  });

  final String inputKey1;
  final String prompt1;
  final String inputKey2;
  final String prompt2;

  @override
  bool isEmpty(Map<String, dynamic> input) =>
      input[inputKey1] == null && input[inputKey2] == null;

  @override
  bool isComplete(Map<String, dynamic> input) {
    final v1 = input[inputKey1] as String?;
    final v2 = input[inputKey2] as String?;
    return v1 != null && v1.isNotEmpty && v2 != null && v2.isNotEmpty;
  }

  @override
  Map<String, dynamic> defaults(List<Player> players) => {
    inputKey1: null,
    inputKey2: null,
  };
}
