import 'double_matrix.dart';
import 'games/game_catalog.dart';
import 'player.dart';
import 'round_record.dart';

/// A mini-game round that was started but not fully scored.
/// Stored inside [GameSession] so partial input survives app restarts.
class PendingRound {
  const PendingRound({
    required this.gameId,
    required this.gameName,
    required this.chooserId,
    this.input = const {},
    this.doublesJson,
  });

  final String gameId;
  final String gameName;

  /// The player ID of the chooser for this round.
  ///
  /// The dealer is derived from [chooserId] via [dealerIndexFor] — not stored.
  final String chooserId;

  final Map<String, dynamic> input;
  final Map<String, dynamic>? doublesJson;

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'gameName': gameName,
    'chooserId': chooserId,
    'input': input,
    if (doublesJson != null) 'doublesJson': doublesJson,
  };

  factory PendingRound.fromJson(Map<String, dynamic> json) => PendingRound(
    gameId: json['gameId'] as String,
    gameName: json['gameName'] as String,
    chooserId: json['chooserId'] as String,
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
    required this.players,
    required this.firstDealerId,
    required this.rounds,
    this.pendingRound,
  });

  /// Unique identifier – microseconds-since-epoch string generated at start.
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The four players in seat order.
  final List<Player> players;

  /// The ID of the player who deals round 1.
  ///
  /// Used to compute the dealer for the next new round:
  ///   dealer for round N = players[(firstDealerIdx + N − 1) % 4]
  ///
  /// Stored as a game property so it survives restarts even before any round
  /// has been played.
  final String firstDealerId;

  /// All completed rounds in chronological order.
  final List<RoundRecord> rounds;

  /// A round that was started but not fully scored; null when none.
  final PendingRound? pendingRound;

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  /// A Bonken game consists of 12 rounds (8 negative + 4 of 5 positive).
  static const int totalRounds = 12;

  /// True when all [totalRounds] rounds have been played.
  bool get isFinished => rounds.length >= totalRounds;

  /// Seat index of the round-1 dealer.
  late final int firstDealerIndex = seatIndexOf(players, firstDealerId);

  /// Players in display order — starting from the round-1 dealer, rotating forward.
  late final List<Player> displayedPlayers = rotatedFromDealer(
    players,
    firstDealerId,
  );

  /// Player names in display order.
  late final List<String> displayedPlayerNames = List.unmodifiable([
    for (final p in displayedPlayers) p.name,
  ]);

  /// Cumulative score for each player, keyed by player ID.
  late final Map<String, int> finalScoresByPlayer = () {
    final totals = <String, int>{for (final p in players) p.id: 0};
    for (final r in rounds) {
      for (final p in players) {
        totals[p.id] = totals[p.id]! + (r.scoresByPlayer[p.id] ?? 0);
      }
    }
    return Map<String, int>.unmodifiable(totals);
  }();

  /// Cumulative scores in display order.
  late final List<int> displayedScores = [
    for (final p in displayedPlayers) finalScoresByPlayer[p.id] ?? 0,
  ];

  /// Player IDs of the winner(s) — the player(s) with the highest score.
  late final List<String> winnerIds = () {
    if (rounds.isEmpty) return <String>[];
    final best = finalScoresByPlayer.values.reduce((a, b) => a > b ? a : b);
    return [
      for (final e in finalScoresByPlayer.entries)
        if (e.value == best) e.key,
    ];
  }();

  /// Indices of winner(s) within [displayedPlayers] — for use with [ScoreboardCard].
  late final List<int> displayedWinnerIndices = [
    for (int i = 0; i < displayedPlayers.length; i++)
      if (winnerIds.contains(displayedPlayers[i].id)) i,
  ];

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'players': [for (final p in players) p.toJson()],
    'firstDealerId': firstDealerId,
    'rounds': [for (final r in rounds) r.toJson()],
    if (pendingRound != null) 'pendingRound': pendingRound!.toJson(),
  };

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final players = [
      for (final p in json['players'] as List)
        Player.fromJson(p as Map<String, dynamic>),
    ];
    return GameSession(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      players: players,
      firstDealerId: json['firstDealerId'] as String,
      rounds: [
        for (final r in json['rounds'] as List)
          _roundFromJson(r as Map<String, dynamic>),
      ],
      pendingRound: json['pendingRound'] != null
          ? PendingRound.fromJson(json['pendingRound'] as Map<String, dynamic>)
          : null,
    );
  }

  static RoundRecord _roundFromJson(Map<String, dynamic> json) => RoundRecord(
    roundNumber: json['roundNumber'] as int,
    game: allGames.firstWhere(
      (g) => g.id == json['gameId'] as String,
      orElse: () => allGames.first,
    ),
    chooserId: json['chooserId'] as String,
    scoresByPlayer: Map<String, int>.from(json['scores'] as Map),
    input: (json['input'] as Map<String, dynamic>?) ?? const {},
    doubles: json['doublesJson'] != null
        ? DoubleMatrix.fromJson(json['doublesJson'] as Map<String, dynamic>)
        : const DoubleMatrix(),
  );
}
