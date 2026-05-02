/// A simplified record of one completed round, stored inside a [GameSession].
class RoundSummary {
  const RoundSummary({
    required this.roundNumber,
    required this.gameName,
    required this.gameId,
    required this.dealerIndex,
    required this.chooserIndex,
    required this.scores,
    this.input,
    this.doublesJson,
  });

  final int roundNumber;
  final String gameName;
  final String gameId;
  final int dealerIndex;
  final int chooserIndex;

  /// Maps player index (0–3) → score delta for this round.
  final Map<int, int> scores;

  /// Full game input map, stored so the round can be reopened for re-editing.
  final Map<String, dynamic>? input;

  /// Serialised [DoubleMatrix], stored alongside input for re-editing.
  final Map<String, dynamic>? doublesJson;

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'gameName': gameName,
    'gameId': gameId,
    'dealerIndex': dealerIndex,
    'chooserIndex': chooserIndex,
    // JSON keys must be strings.
    'scores': {for (final e in scores.entries) '${e.key}': e.value},
    if (input != null) 'input': input,
    if (doublesJson != null) 'doublesJson': doublesJson,
  };

  factory RoundSummary.fromJson(Map<String, dynamic> json) => RoundSummary(
    roundNumber: json['roundNumber'] as int,
    gameName: json['gameName'] as String,
    gameId: json['gameId'] as String,
    dealerIndex: json['dealerIndex'] as int,
    chooserIndex: json['chooserIndex'] as int,
    scores: {
      for (final e in (json['scores'] as Map<String, dynamic>).entries)
        int.parse(e.key): e.value as int,
    },
    input: json['input'] as Map<String, dynamic>?,
    doublesJson: json['doublesJson'] as Map<String, dynamic>?,
  );
}

/// A mini-game round that was started but not fully scored.
/// Stored inside [GameSession] so partial input survives app restarts.
class PendingRound {
  const PendingRound({
    required this.gameId,
    required this.gameName,
    required this.dealerIndex,
    required this.chooserIndex,
    this.input = const {},
    this.doublesJson,
  });

  final String gameId;
  final String gameName;
  final int dealerIndex;
  final int chooserIndex;
  final Map<String, dynamic> input;
  final Map<String, dynamic>? doublesJson;

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'gameName': gameName,
    'dealerIndex': dealerIndex,
    'chooserIndex': chooserIndex,
    'input': input,
    if (doublesJson != null) 'doublesJson': doublesJson,
  };

  factory PendingRound.fromJson(Map<String, dynamic> json) => PendingRound(
    gameId: json['gameId'] as String,
    gameName: json['gameName'] as String,
    dealerIndex: json['dealerIndex'] as int,
    chooserIndex: json['chooserIndex'] as int,
    input: (json['input'] as Map<String, dynamic>?) ?? const {},
    doublesJson: json['doublesJson'] as Map<String, dynamic>?,
  );
}

/// A complete record of a saved game session (finished or closed mid-game).
class GameSession {
  GameSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.playerNames,
    required this.rounds,
    this.pendingRound,
  });

  /// Unique identifier – microseconds-since-epoch string generated at start.
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The four player names, in seat order.
  final List<String> playerNames;

  /// All completed rounds in chronological order.
  final List<RoundSummary> rounds;

  /// A round that was started but not fully scored; null when none.
  final PendingRound? pendingRound;

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  /// A Bonken game consists of 12 rounds (8 negative + 4 of 5 positive).
  static const int totalRounds = 12;

  /// True when all [totalRounds] rounds have been played.
  bool get isFinished => rounds.length >= totalRounds;

  /// Cumulative score for each player index.
  ///
  /// Computed lazily on first access and cached \u2014 the StartScreen card
  /// reads this multiple times per build (header + winners + sub-text).
  late final Map<int, int> finalScores = _computeFinalScores();

  Map<int, int> _computeFinalScores() {
    final totals = <int, int>{0: 0, 1: 0, 2: 0, 3: 0};
    for (final r in rounds) {
      for (final e in r.scores.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
      }
    }
    return totals;
  }

  /// Indices of all players sharing the highest final score, or empty if no rounds.
  late final List<int> winnerIndices = _computeWinnerIndices();

  List<int> _computeWinnerIndices() {
    if (rounds.isEmpty) return const [];
    final scores = finalScores;
    final best = scores.values.reduce((a, b) => a > b ? a : b);
    return scores.entries
        .where((e) => e.value == best)
        .map((e) => e.key)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'playerNames': playerNames,
    'rounds': [for (final r in rounds) r.toJson()],
    if (pendingRound != null) 'pendingRound': pendingRound!.toJson(),
  };

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    playerNames: List<String>.from(json['playerNames'] as List),
    rounds: [
      for (final r in json['rounds'] as List)
        RoundSummary.fromJson(r as Map<String, dynamic>),
    ],
    pendingRound: json['pendingRound'] != null
        ? PendingRound.fromJson(json['pendingRound'] as Map<String, dynamic>)
        : null,
  );
}
