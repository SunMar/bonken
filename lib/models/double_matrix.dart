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
/// Pairs and initiators are keyed by **player UUID strings** (not seat indices)
/// so they survive player reordering without going stale.
///
/// For a 4-player game the six pairs are all combinations of the four IDs.
/// Pairs are stored with the lexicographically smaller ID first so lookup
/// is canonical regardless of argument order.
///
/// The multiplier for a pair:
///   none      → 0  (pair is ignored in score settlement)
///   doubled   → 1  (pair difference counted once)
///   redoubled → 2  (pair difference counted twice)
///
/// The initiator (null when state is none) is the player ID who made the
/// original double. It does not affect the score calculation but is used by
/// the UI to show direction (e.g. "A dubbelt B") and to correctly label who
/// can redouble.
class DoubleMatrix {
  const DoubleMatrix({this._pairs = const {}, this._initiators = const {}});

  final Map<(String, String), DoubleState> _pairs;

  /// Maps canonical pair key → the player UUID who initiated the double.
  /// Only set when the pair's state is [DoubleState.doubled] or
  /// [DoubleState.redoubled].
  final Map<(String, String), String> _initiators;

  static (String, String) _key(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);

  DoubleState stateFor(String playerA, String playerB) =>
      _pairs[_key(playerA, playerB)] ?? DoubleState.none;

  /// The player UUID who initiated the double for this pair, or null if
  /// neither player has doubled the other.
  String? initiatorFor(String playerA, String playerB) =>
      _initiators[_key(playerA, playerB)];

  int multiplierFor(String playerA, String playerB) =>
      switch (stateFor(playerA, playerB)) {
        DoubleState.none => 0,
        DoubleState.doubled => 1,
        DoubleState.redoubled => 2,
      };

  /// Set the state for a pair and record who initiated.
  /// Pass [initiator] = null to clear the pair (state → none).
  DoubleMatrix withPair(
    String playerA,
    String playerB,
    DoubleState state, {
    String? initiator,
  }) {
    final key = _key(playerA, playerB);
    final updatedPairs = Map<(String, String), DoubleState>.from(_pairs);
    final updatedInitiators = Map<(String, String), String>.from(_initiators);

    if (state == DoubleState.none) {
      updatedPairs.remove(key);
      updatedInitiators.remove(key);
    } else {
      updatedPairs[key] = state;
      if (initiator != null) updatedInitiators[key] = initiator;
    }

    return DoubleMatrix(pairs: updatedPairs, initiators: updatedInitiators);
  }

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
  // JSON serialisation — pair keys are encoded as "<uuidA>,<uuidB>" strings
  // where uuidA is the lexicographically smaller of the two.
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
    (String, String) parseKey(String k) {
      final comma = k.indexOf(',');
      return (k.substring(0, comma), k.substring(comma + 1));
    }

    final pairsRaw = (json['pairs'] as Map<String, dynamic>?) ?? {};
    final initRaw = (json['initiators'] as Map<String, dynamic>?) ?? {};

    return DoubleMatrix(
      pairs: {
        for (final e in pairsRaw.entries)
          parseKey(e.key): DoubleState.values.byName(e.value as String),
      },
      initiators: {
        for (final e in initRaw.entries) parseKey(e.key): e.value as String,
      },
    );
  }
}
