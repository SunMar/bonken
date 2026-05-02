import 'mini_game.dart';

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
  Map<String, dynamic> defaults();
}

/// A mini-game where each of the 4 players enters a count (tricks or scoring
/// cards won). The four values must sum to [total].
class CountsInputDescriptor extends InputDescriptor {
  const CountsInputDescriptor({
    required this.inputKey,
    required this.total,
    required this.unitLabel,
  });

  /// Key used in the input map (e.g. 'tricks', 'cards').
  final String inputKey;

  /// Required sum of all four player counts.
  final int total;

  /// Human-readable unit shown next to the count (Dutch, e.g. 'slagen').
  final String unitLabel;

  @override
  bool isEmpty(Map<String, dynamic> input) {
    final counts = (input[inputKey] as List?)?.cast<int>();
    if (counts == null) return true;
    return counts.fold<int>(0, (a, b) => a + b) == 0;
  }

  @override
  bool isComplete(Map<String, dynamic> input) {
    final counts = (input[inputKey] as List?)?.cast<int>();
    if (counts == null) return false;
    return counts.fold<int>(0, (a, b) => a + b) == total;
  }

  @override
  Map<String, dynamic> defaults() => {inputKey: List.filled(playerCount, 0)};
}

/// A mini-game where a single player is selected (winner or loser).
class SinglePlayerInputDescriptor extends InputDescriptor {
  const SinglePlayerInputDescriptor({
    required this.inputKey,
    required this.prompt,
  });

  /// Key used in the input map (e.g. 'winner', 'loser').
  final String inputKey;

  /// Question shown above the player selector (Dutch).
  final String prompt;

  @override
  bool isEmpty(Map<String, dynamic> input) => input[inputKey] == null;

  @override
  bool isComplete(Map<String, dynamic> input) {
    final v = input[inputKey];
    return v != null && (v as int) >= 0;
  }

  @override
  Map<String, dynamic> defaults() => {inputKey: null};
}

/// A mini-game with two independent player selections (7e / 13e).
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
    final v1 = input[inputKey1];
    final v2 = input[inputKey2];
    return v1 != null && (v1 as int) >= 0 && v2 != null && (v2 as int) >= 0;
  }

  @override
  Map<String, dynamic> defaults() => {inputKey1: null, inputKey2: null};
}
