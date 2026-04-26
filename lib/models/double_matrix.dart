/// The doubling state between two players.
enum DoubleState {
  /// Neither player doubled the other — pair difference is ignored.
  none,

  /// One player doubled the other — pair difference is applied once.
  doubled,

  /// The doubled player redoubled — pair difference is applied twice.
  redoubled,
}

/// Holds the doubling/redoubling state for every pair of players, including
/// which player initiated the double (the "initiator").
///
/// For a 4-player game the six pairs are: (0,1) (0,2) (0,3) (1,2) (1,3) (2,3).
/// Pairs are stored with the lower index first so lookup is canonical.
///
/// The multiplier for a pair:
///   none      → 0  (pair is ignored in score settlement)
///   doubled   → 1  (pair difference counted once)
///   redoubled → 2  (pair difference counted twice)
///
/// The initiator (null when state is none) is the player who made the original
/// double.  It does not affect the score calculation but is used by the UI to
/// show direction (e.g. "A dubbelt B") and to correctly label who can redouble.
class DoubleMatrix {
  const DoubleMatrix({
    Map<(int, int), DoubleState> pairs = const {},
    Map<(int, int), int> initiators = const {},
  }) : _pairs = pairs,
       _initiators = initiators;

  final Map<(int, int), DoubleState> _pairs;

  /// Maps canonical pair key → the player index who initiated the double.
  /// Only set when the pair's state is [DoubleState.doubled] or
  /// [DoubleState.redoubled].
  final Map<(int, int), int> _initiators;

  static (int, int) _key(int a, int b) => a < b ? (a, b) : (b, a);

  DoubleState stateFor(int playerA, int playerB) =>
      _pairs[_key(playerA, playerB)] ?? DoubleState.none;

  /// The player index who initiated the double for this pair, or null if
  /// neither player has doubled the other.
  int? initiatorFor(int playerA, int playerB) =>
      _initiators[_key(playerA, playerB)];

  int multiplierFor(int playerA, int playerB) =>
      switch (stateFor(playerA, playerB)) {
        DoubleState.none => 0,
        DoubleState.doubled => 1,
        DoubleState.redoubled => 2,
      };

  /// Set the state for a pair and record who initiated.
  /// Pass [initiator] = null to clear the pair (state → none).
  DoubleMatrix withPair(
    int playerA,
    int playerB,
    DoubleState state, {
    int? initiator,
  }) {
    final key = _key(playerA, playerB);
    final updatedPairs = Map<(int, int), DoubleState>.from(_pairs);
    final updatedInitiators = Map<(int, int), int>.from(_initiators);

    if (state == DoubleState.none) {
      updatedPairs.remove(key);
      updatedInitiators.remove(key);
    } else {
      updatedPairs[key] = state;
      if (initiator != null) updatedInitiators[key] = initiator;
    }

    return DoubleMatrix(pairs: updatedPairs, initiators: updatedInitiators);
  }

  /// Convenience: kept for backward compatibility with existing tests.
  DoubleMatrix withState(int playerA, int playerB, DoubleState state) =>
      withPair(playerA, playerB, state, initiator: playerA);

  /// Returns a fresh matrix where all pairs are [DoubleState.none].
  static DoubleMatrix empty() => const DoubleMatrix();

  /// True when at least one pair has an active double or redouble.
  bool get hasAnyDouble => _pairs.values.any((s) => s != DoubleState.none);

  @override
  bool operator ==(Object other) {
    if (other is! DoubleMatrix) return false;
    if (_pairs.length != other._pairs.length) return false;
    if (_initiators.length != other._initiators.length) return false;
    for (final e in _pairs.entries) {
      if (other._pairs[e.key] != e.value) return false;
    }
    for (final e in _initiators.entries) {
      if (other._initiators[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      _pairs.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      _initiators.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  // ---------------------------------------------------------------------------
  // JSON serialisation — pair keys are encoded as "a,b" strings.
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'pairs': {
      for (final e in _pairs.entries) '${e.key.$1},${e.key.$2}': e.value.name,
    },
    'initiators': {
      for (final e in _initiators.entries) '${e.key.$1},${e.key.$2}': e.value,
    },
  };

  factory DoubleMatrix.fromJson(Map<String, dynamic> json) {
    (int, int) parseKey(String k) {
      final parts = k.split(',');
      return (int.parse(parts[0]), int.parse(parts[1]));
    }

    final pairsRaw = (json['pairs'] as Map<String, dynamic>?) ?? {};
    final initRaw = (json['initiators'] as Map<String, dynamic>?) ?? {};

    return DoubleMatrix(
      pairs: {
        for (final e in pairsRaw.entries)
          parseKey(e.key): DoubleState.values.byName(e.value as String),
      },
      initiators: {
        for (final e in initRaw.entries) parseKey(e.key): e.value as int,
      },
    );
  }
}
