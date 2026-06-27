import 'double_matrix.dart';
import 'games/game_catalog.dart';
import 'input_descriptor.dart';
import 'player.dart';
import 'round_record.dart';
import 'rule_variants.dart';

/// Extracts the persisted counts list from a stored `input` map
/// (`{'counts': [ {uuid:int}, ... ]}`); `[]` when absent.
List<Map<String, int>> _countsFromInputJson(Map<String, dynamic>? inputJson) {
  final raw = (inputJson?['counts'] as List?) ?? const [];
  // Eager `Map<String, int>.from` (not a lazy `.cast`) so a non-int stored count
  // (e.g. a JS `2.0` / `-0.0` double) throws a `TypeError` here at the parse
  // boundary — mirroring the scores path — instead of deferring past validation
  // into scoring.
  return [for (final m in raw) Map<String, int>.from(m as Map)];
}

/// Per-player cumulative score, summed across [rounds], in the order of
/// [ordered]: result index `i` is the total for `ordered[i]` (missing per-round
/// scores count as 0).
///
/// The single source of truth for "sum the rounds per player" — used by
/// [GameSession]'s derived totals and by the in-game scoreboard / share views.
List<int> cumulativeTotals(Iterable<RoundRecord> rounds, List<Player> ordered) {
  final totals = List<int>.filled(ordered.length, 0);
  for (final r in rounds) {
    for (int i = 0; i < ordered.length; i++) {
      totals[i] += r.scoresByPlayer[ordered[i].id] ?? 0;
    }
  }
  return totals;
}

/// Indices into [totals] holding the maximum value — the leader(s); ties are
/// shared. Empty when [totals] is empty. Callers decide *when* a leader should
/// be crowned (e.g. only once the game is finished).
List<int> leaderIndices(List<int> totals) {
  if (totals.isEmpty) return const [];
  final best = totals.reduce((a, b) => a > b ? a : b);
  return [
    for (int i = 0; i < totals.length; i++)
      if (totals[i] == best) i,
  ];
}

/// A mini-game round that was started but not fully scored.
/// Stored inside [GameSession] so partial input survives app restarts.
class PendingRound {
  const PendingRound({
    required this.gameId,
    required this.chooserId,
    this.input,
    this.doubles,
  });

  final String gameId;

  /// The player ID of the chooser for this round.
  ///
  /// The dealer is derived from [chooserId] via [dealerIndexFor] — not stored.
  final String chooserId;

  final GameInput? input;
  final DoubleMatrix? doubles;

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'chooserId': chooserId,
    'input': {
      'counts': input == null
          ? const <Map<String, int>>[]
          : gameById(gameId).inputToCounts(input!),
    },
    'doublesJson': ?doubles?.toJson(),
  };

  factory PendingRound.fromJson(Map<String, dynamic> json) {
    final gameId = json['gameId'] as String;
    return PendingRound(
      gameId: gameId,
      chooserId: json['chooserId'] as String,
      input: gameById(gameId).countsToInput(
        _countsFromInputJson(json['input'] as Map<String, dynamic>?),
      ),
      doubles: json['doublesJson'] != null
          ? DoubleMatrix.fromJson(json['doublesJson'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// A complete record of a saved game session (finished or closed mid-game).
class GameSession {
  GameSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.scoredAt,
    required this.players,
    required this.firstDealerId,
    required this.rounds,
    this.pendingRound,
    this.ruleVariants = const RuleVariants(),
    this.gameName,
  });

  /// Unique identifier – UUID v4 generated at session start.
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When scores last changed — advances only when a [RoundRecord] is
  /// committed (round appended, replaced, or deleted). Player/name/rule edits
  /// leave this unchanged. Starts at [createdAt] for new sessions.
  final DateTime scoredAt;

  /// Optional user-supplied name for this game session. Never the empty string
  /// — callers must pass null rather than `''`.
  final String? gameName;

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

  /// The per-game rule variants (starter + hearts) chosen for this session.
  final RuleVariants ruleVariants;

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  /// A Bonken game consists of 12 rounds (8 negative + 4 of 5 positive).
  static const int totalRounds = 12;

  /// True when all [totalRounds] rounds have been played.
  bool get isFinished => rounds.length >= totalRounds;

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
    final totals = cumulativeTotals(rounds, players);
    return Map<String, int>.unmodifiable({
      for (int i = 0; i < players.length; i++) players[i].id: totals[i],
    });
  }();

  /// Cumulative scores in display order.
  late final List<int> displayedScores = cumulativeTotals(
    rounds,
    displayedPlayers,
  );

  /// Indices of winner(s) within [displayedPlayers] — for use with
  /// [ScoreboardCard]. Empty before any round is played (no leader to crown yet).
  late final List<int> displayedWinnerIndices = rounds.isEmpty
      ? const []
      : leaderIndices(displayedScores);

  /// Player IDs of the winner(s) — the player(s) with the highest score.
  late final List<String> winnerIds = [
    for (final i in displayedWinnerIndices) displayedPlayers[i].id,
  ];

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'scoredAt': scoredAt.toIso8601String(),
    'gameName': ?gameName,
    'players': [for (final p in players) p.toJson()],
    'firstDealerId': firstDealerId,
    'ruleVariants': ruleVariants.toJson(),
    'rounds': [for (final r in rounds) r.toJson()],
    'pendingRound': ?pendingRound?.toJson(),
  };

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final players = [
      for (final p in json['players'] as List)
        Player.fromJson(p as Map<String, dynamic>),
    ];
    _validateReferences(players, json);
    return GameSession(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      scoredAt: DateTime.parse(json['scoredAt'] as String),
      players: players,
      firstDealerId: json['firstDealerId'] as String,
      ruleVariants: RuleVariants.fromJson(
        (json['ruleVariants'] as Map<String, dynamic>?) ?? const {},
      ),
      rounds: [
        for (final r in json['rounds'] as List)
          _roundFromJson(r as Map<String, dynamic>),
      ],
      pendingRound: json['pendingRound'] != null
          ? PendingRound.fromJson(json['pendingRound'] as Map<String, dynamic>)
          : null,
      gameName: json['gameName'] as String?,
    );
  }

  // Validates every player-id reference in the raw JSON before any round or
  // pending-round objects are constructed. A dangling ref throws, which is
  // caught by the `on Object` boundary in GameHistoryNotifier.build() and
  // surfaces as a CorruptPersistenceException. Game ids are already validated by
  // gameById() during construction and need not be repeated here.
  static void _validateReferences(
    List<Player> players,
    Map<String, dynamic> json,
  ) {
    final validIds = {for (final p in players) p.id};

    void checkId(String id, String context) {
      if (!validIds.contains(id)) {
        throw StateError('$context "$id" not among session players');
      }
    }

    void checkGameId(String id, String context) {
      if (allGames.every((g) => g.id != id)) {
        throw StateError('$context game id "$id" is not a known game');
      }
    }

    void checkDoublesJson(Map<String, dynamic> doublesJson, String ctx) {
      for (final entry in doublesJson.entries) {
        final comma = entry.key.indexOf(',');
        if (comma < 0) {
          throw StateError('$ctx doubles pair key "${entry.key}" is malformed');
        }
        final a = entry.key.substring(0, comma);
        final b = entry.key.substring(comma + 1);
        // Pair keys are stored canonically (smaller id first); a non-canonical
        // key from a hand-edited/foreign backup would silently miss every lookup
        // (which canonicalizes), so reject it as corrupt at the boundary.
        if (a.compareTo(b) > 0) {
          throw StateError(
            '$ctx doubles pair key "${entry.key}" is not in canonical order',
          );
        }
        checkId(a, '$ctx doubles pair A');
        checkId(b, '$ctx doubles pair B');
        checkId(
          (entry.value as Map<String, dynamic>)['initiator'] as String,
          '$ctx doubles initiator',
        );
      }
    }

    checkId(json['firstDealerId'] as String, 'firstDealerId');

    for (final r in json['rounds'] as List) {
      final roundJson = r as Map<String, dynamic>;
      final n = roundJson['roundNumber'];
      checkGameId(roundJson['gameId'] as String, 'round $n');
      checkId(roundJson['chooserId'] as String, 'round $n chooserId');
      for (final id in (roundJson['scores'] as Map).keys) {
        checkId(id as String, 'round $n scoresByPlayer key');
      }
      final inputJson = roundJson['input'] as Map<String, dynamic>?;
      if (inputJson != null) {
        for (final m in (inputJson['counts'] as List? ?? const <dynamic>[])) {
          for (final id in (m as Map).keys) {
            checkId(id as String, 'round $n input counts key');
          }
        }
      }
      final doublesJson = roundJson['doublesJson'] as Map<String, dynamic>?;
      if (doublesJson != null) checkDoublesJson(doublesJson, 'round $n');
    }

    final pendingJson = json['pendingRound'] as Map<String, dynamic>?;
    if (pendingJson != null) {
      checkGameId(pendingJson['gameId'] as String, 'pendingRound');
      checkId(pendingJson['chooserId'] as String, 'pendingRound chooserId');
      final inputJson = pendingJson['input'] as Map<String, dynamic>?;
      if (inputJson != null) {
        for (final m in (inputJson['counts'] as List? ?? const <dynamic>[])) {
          for (final id in (m as Map).keys) {
            checkId(id as String, 'pendingRound input counts key');
          }
        }
      }
      final doublesJson = pendingJson['doublesJson'] as Map<String, dynamic>?;
      if (doublesJson != null) checkDoublesJson(doublesJson, 'pendingRound');
    }
  }

  static RoundRecord _roundFromJson(Map<String, dynamic> json) {
    final game = gameById(json['gameId'] as String);
    return RoundRecord(
      roundNumber: json['roundNumber'] as int,
      game: game,
      chooserId: json['chooserId'] as String,
      scoresByPlayer: Map<String, int>.from(json['scores'] as Map),
      input: game.countsToInput(
        _countsFromInputJson(json['input'] as Map<String, dynamic>?),
      ),
      doubles: json['doublesJson'] != null
          ? DoubleMatrix.fromJson(json['doublesJson'] as Map<String, dynamic>)
          : const DoubleMatrix(),
    );
  }
}
