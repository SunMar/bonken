/// Describes the input fields required by a mini-game so the UI can render
/// the correct form without knowing concrete game types.
sealed class InputDescriptor {
  const InputDescriptor();
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
}
