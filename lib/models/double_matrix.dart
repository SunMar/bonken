/// The doubling state between two players.
enum DoubleState {
  /// Neither player doubled the other — pair difference is ignored.
  none,

  /// One player doubled the other — pair difference is applied once.
  doubled,

  /// The doubled player redoubled — pair difference is applied twice.
  redoubled,
}

/// State + initiator for one active pair — both fields are always present
/// when a pair is in [DoubleState.doubled] or [DoubleState.redoubled].
typedef _PairState = ({DoubleState state, String initiator});

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
  const DoubleMatrix({this._pairs = const {}});

  final Map<(String, String), _PairState> _pairs;

  static (String, String) _key(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);

  DoubleState stateFor(String playerA, String playerB) =>
      _pairs[_key(playerA, playerB)]?.state ?? DoubleState.none;

  /// The player UUID who initiated the double for this pair, or null if
  /// neither player has doubled the other.
  String? initiatorFor(String playerA, String playerB) =>
      _pairs[_key(playerA, playerB)]?.initiator;

  int multiplierFor(String playerA, String playerB) =>
      switch (stateFor(playerA, playerB)) {
        .none => 0,
        .doubled => 1,
        .redoubled => 2,
      };

  /// Set the state for a pair and record who initiated.
  /// Pass [initiator] = null to clear the pair (state → none).
  DoubleMatrix withPair(
    String playerA,
    String playerB,
    DoubleState state, {
    String? initiator,
  }) {
    assert(state == DoubleState.none || initiator != null);
    final key = _key(playerA, playerB);
    final updated = Map<(String, String), _PairState>.from(_pairs);
    if (state == DoubleState.none) {
      updated.remove(key);
    } else {
      updated[key] = (state: state, initiator: initiator!);
    }
    return DoubleMatrix(pairs: updated);
  }

  /// True when at least one pair has an active double or redouble.
  bool get hasAnyDouble => _pairs.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! DoubleMatrix) return false;
    if (_pairs.length != other._pairs.length) return false;
    for (final e in _pairs.entries) {
      if (other._pairs[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _pairs.entries.map(
      (e) => Object.hash(e.key, e.value.state, e.value.initiator),
    ),
  );

  // ---------------------------------------------------------------------------
  // JSON serialisation — pair keys are encoded as "<uuidA>,<uuidB>" strings
  // where uuidA is the lexicographically smaller of the two.
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    for (final e in _pairs.entries)
      '${e.key.$1},${e.key.$2}': {
        'state': e.value.state.name,
        'initiator': e.value.initiator,
      },
  };

  factory DoubleMatrix.fromJson(Map<String, dynamic> json) {
    (String, String) parseKey(String k) {
      final comma = k.indexOf(',');
      if (comma < 0) {
        throw FormatException(
          'DoubleMatrix pair key has no comma separator',
          k,
        );
      }
      return (k.substring(0, comma), k.substring(comma + 1));
    }

    return DoubleMatrix(
      pairs: {
        for (final e in json.entries)
          parseKey(e.key): (
            state: DoubleState.values.byName(
              (e.value as Map<String, dynamic>)['state'] as String,
            ),
            initiator: (e.value as Map<String, dynamic>)['initiator'] as String,
          ),
      },
    );
  }
}
