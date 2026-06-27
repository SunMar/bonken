import 'package:uuid/uuid.dart';

import '../models/player.dart';

const _uuid = Uuid();

/// One forward storage step: data at [fromVersion] → data at [fromVersion] + 1.
///
/// Steps are **frozen and self-contained**: each carries whatever historical
/// schema knowledge it needs and never reads from live game code (descriptors,
/// keys, classes). That way an old step keeps working unchanged forever, no
/// matter how the current models evolve.
abstract class StorageMigration {
  const StorageMigration();

  /// The version this step upgrades *from*.
  int get fromVersion;

  /// Transforms the `games` list from [fromVersion] to [fromVersion] + 1.
  List<dynamic> apply(List<dynamic> games);
}

/// Latest on-disk schema version. Bumped whenever a new step is appended.
const int currentStorageVersion = 11;

/// Ordered registry — append one entry per new version. Nothing else changes.
const List<StorageMigration> _migrations = [
  _V1ToV2(),
  _V2ToV3(),
  _V3ToV4(),
  _V4ToV5(),
  _V5ToV6(),
  _V6ToV7(),
  _V7ToV8(),
  _V8ToV9(),
  _V9ToV10(),
  _V10ToV11(),
];

/// Applies every registered step from [fromVersion] up to
/// [currentStorageVersion], in order, returning the upgraded games list.
List<dynamic> runStorageMigrations(
  List<dynamic> games, {
  required int fromVersion,
}) {
  var data = games;
  var v = fromVersion;
  for (final migration in _migrations) {
    if (migration.fromVersion != v) continue;
    data = migration.apply(data);
    v++;
  }
  // Fail loudly in release too (not just a debug `assert`): a mis-registered or
  // out-of-order step would otherwise silently return partially-migrated data
  // that gets stamped at the current version — the exact version-stamp-lie class
  // of bug. Throwing turns that into a loud CorruptPersistenceException on load.
  if (v != currentStorageVersion) {
    throw StateError(
      'migration chain stalled at v$v (expected $currentStorageVersion)',
    );
  }
  return data;
}

/// Input shape of a game's stored input, as it existed in the pre-v3 schema.
enum _Shape { counts, single, dual }

// =============================================================================
// v1 → v2 : seat-index-keyed → UUID-keyed values (keys unchanged)
// =============================================================================
//
// v1 stored:
//   • playerNames: List<String> (no UUIDs)
//   • rounds[].dealerIndex + chooserIndex (ints)
//   • rounds[].scores: {"0": v, ...} (index-keyed)
//   • rounds[].input: index-keyed (List<int> for counts, int? for single/dual)
//   • rounds[].doublesJson: pair keys "a,b" with integer seat indices
//   • pendingRound.dealerIndex + chooserIndex
//
// v2 stores the same input *keys*, but values keyed by the freshly-minted
// player UUIDs.

class _V1ToV2 extends StorageMigration {
  const _V1ToV2();

  @override
  int get fromVersion => 1;

  /// Frozen v1 input schema (this step's own copy — see [StorageMigration]).
  static const Map<String, (_Shape, List<String>)> _schema = {
    'kingOfHearts': (_Shape.single, ['winner']),
    'finalTrick': (_Shape.single, ['winner']),
    'dominoes': (_Shape.single, ['loser']),
    'seventhAndThirteenth': (_Shape.dual, ['trick7winner', 'trick13winner']),
    'kingsAndJacks': (_Shape.counts, ['cards']),
    'queens': (_Shape.counts, ['cards']),
    'duck': (_Shape.counts, ['tricks']),
    'heartPoints': (_Shape.counts, ['cards']),
    'clubs': (_Shape.counts, ['tricks']),
    'diamonds': (_Shape.counts, ['tricks']),
    'hearts': (_Shape.counts, ['tricks']),
    'spades': (_Shape.counts, ['tricks']),
    'noTrump': (_Shape.counts, ['tricks']),
  };

  @override
  List<dynamic> apply(List<dynamic> games) {
    final v2Games = <Map<String, dynamic>>[];
    for (final raw in games) {
      final game = raw as Map<String, dynamic>;
      final playerNames = (game['playerNames'] as List<dynamic>)
          .map((n) => n as String)
          .toList();

      // Generate stable UUIDs for each player in seat order.
      final players = [for (final name in playerNames) Player(name: name)];
      final playersJson = [for (final p in players) p.toJson()];
      final playerIds = [for (final p in players) p.id];

      final rounds = (game['rounds'] as List<dynamic>?) ?? [];
      final pendingRaw = game['pendingRound'] as Map<String, dynamic>?;

      // Back-compute firstDealerIdx from the last known dealer:
      //   • pending round → its dealerIndex is the current dealer for round
      //     (rounds.length + 1): firstDealerIdx = (pendingDealerIdx - len) mod 4
      //   • else last completed round dealt round len:
      //     firstDealerIdx = (lastDealerIdx - len + 1) mod 4
      //   • no rounds → 0.
      int firstDealerIdx;
      if (pendingRaw != null) {
        final pendingDealerIdx = (pendingRaw['dealerIndex'] as int?) ?? 0;
        firstDealerIdx = ((pendingDealerIdx - rounds.length) % 4 + 4) % 4;
      } else if (rounds.isNotEmpty) {
        final lastRound = rounds.last as Map<String, dynamic>;
        final lastDealerIdx = (lastRound['dealerIndex'] as int?) ?? 0;
        firstDealerIdx = ((lastDealerIdx - rounds.length + 1) % 4 + 4) % 4;
      } else {
        firstDealerIdx = 0;
      }
      final firstDealerId = players[firstDealerIdx].id;

      final v2Rounds = <Map<String, dynamic>>[];
      for (final r in rounds) {
        final round = r as Map<String, dynamic>;
        final chooserIdx = (round['chooserIndex'] as int?) ?? 0;
        final chooserId = players[chooserIdx.clamp(0, 3)].id;

        // v1 scores: {"0": v, ...} — keys are stringified seat indices.
        final v1Scores = round['scores'] as Map<String, dynamic>? ?? {};
        final v2Scores = <String, dynamic>{
          for (final e in v1Scores.entries)
            players[int.tryParse(e.key)?.clamp(0, 3) ?? 0].id: e.value,
        };

        final gameId = round['gameId'] as String;
        final inputRaw = (round['input'] as Map<String, dynamic>?) ?? {};
        final doublesRaw = round['doublesJson'] as Map<String, dynamic>?;

        v2Rounds.add({
          'roundNumber': round['roundNumber'],
          'gameName': round['gameName'],
          'gameId': gameId,
          'chooserId': chooserId,
          'scores': v2Scores,
          'input': _migrateInput(gameId, inputRaw, playerIds),
          if (doublesRaw != null)
            'doublesJson': _migrateDoubles(doublesRaw, playerIds),
        });
      }

      Map<String, dynamic>? v2Pending;
      if (pendingRaw != null) {
        final chooserIdx = (pendingRaw['chooserIndex'] as int?) ?? 0;
        final chooserId = players[chooserIdx.clamp(0, 3)].id;
        final gameId = pendingRaw['gameId'] as String;
        final inputRaw = (pendingRaw['input'] as Map<String, dynamic>?) ?? {};
        final doublesRaw = pendingRaw['doublesJson'] as Map<String, dynamic>?;
        v2Pending = {
          'gameId': gameId,
          'gameName': pendingRaw['gameName'],
          'chooserId': chooserId,
          'input': _migrateInput(gameId, inputRaw, playerIds),
          if (doublesRaw != null)
            'doublesJson': _migrateDoubles(doublesRaw, playerIds),
        };
      }

      v2Games.add({
        'id': game['id'],
        'createdAt': game['createdAt'],
        'updatedAt': game['updatedAt'],
        'players': playersJson,
        'firstDealerId': firstDealerId,
        'rounds': v2Rounds,
        'pendingRound': v2Pending,
      });
    }
    return v2Games;
  }

  /// v1 index-keyed input → v2 UUID-keyed input, keeping the (old) keys.
  static Map<String, dynamic> _migrateInput(
    String gameId,
    Map<String, dynamic> input,
    List<String> playerIds,
  ) {
    final entry = _schema[gameId];
    if (entry == null) return input; // unknown game — leave untouched
    final (shape, keys) = entry;
    String pid(int idx) => playerIds[idx.clamp(0, playerIds.length - 1)];
    switch (shape) {
      case _Shape.counts:
        final list = (input[keys[0]] as List?)?.cast<int>();
        if (list == null) return input;
        return {
          keys[0]: {
            for (int i = 0; i < playerIds.length; i++) playerIds[i]: list[i],
          },
        };
      case _Shape.single:
        final idx = input[keys[0]] as int?;
        return {keys[0]: idx == null ? null : pid(idx)};
      case _Shape.dual:
        final idx1 = input[keys[0]] as int?;
        final idx2 = input[keys[1]] as int?;
        return {
          keys[0]: idx1 == null ? null : pid(idx1),
          keys[1]: idx2 == null ? null : pid(idx2),
        };
    }
  }

  static Map<String, dynamic> _migrateDoubles(
    Map<String, dynamic> doublesJson,
    List<String> playerIds,
  ) {
    String migrateKey(String k) {
      final parts = k.split(',');
      final a = playerIds[int.parse(parts[0])];
      final b = playerIds[int.parse(parts[1])];
      return a.compareTo(b) <= 0 ? '$a,$b' : '$b,$a';
    }

    final pairsRaw = (doublesJson['pairs'] as Map<String, dynamic>?) ?? {};
    final initRaw = (doublesJson['initiators'] as Map<String, dynamic>?) ?? {};
    return {
      'pairs': {for (final e in pairsRaw.entries) migrateKey(e.key): e.value},
      'initiators': {
        for (final e in initRaw.entries)
          migrateKey(e.key):
              playerIds[(e.value as int).clamp(0, playerIds.length - 1)],
      },
    };
  }
}

// =============================================================================
// v2 → v3 : per-game input keys → one uniform, lossless counts list
// =============================================================================
//
// v2 input is per-game-keyed (e.g. {'tricks': {uuid:int}}, {'winner': uuid},
// {'trick7winner': uuid, 'trick13winner': uuid}). v3 collapses every shape to a
// single structure: {'counts': [ {uuid:int}, ... ]} — one element for counts and
// single-player games, two positional elements for dual-player games (so the
// 7th vs 13th identity is preserved). Scoring sums element-wise per player.

class _V2ToV3 extends StorageMigration {
  const _V2ToV3();

  @override
  int get fromVersion => 2;

  /// Frozen v2 input schema (this step's own copy — see [StorageMigration]).
  static const Map<String, (_Shape, List<String>)> _schema = {
    'kingOfHearts': (_Shape.single, ['winner']),
    'finalTrick': (_Shape.single, ['winner']),
    'dominoes': (_Shape.single, ['loser']),
    'seventhAndThirteenth': (_Shape.dual, ['trick7winner', 'trick13winner']),
    'kingsAndJacks': (_Shape.counts, ['cards']),
    'queens': (_Shape.counts, ['cards']),
    'duck': (_Shape.counts, ['tricks']),
    'heartPoints': (_Shape.counts, ['cards']),
    'clubs': (_Shape.counts, ['tricks']),
    'diamonds': (_Shape.counts, ['tricks']),
    'hearts': (_Shape.counts, ['tricks']),
    'spades': (_Shape.counts, ['tricks']),
    'noTrump': (_Shape.counts, ['tricks']),
  };

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _migrateGame(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _migrateGame(Map<String, dynamic> game) => {
    ...game,
    'rounds': [
      for (final r in (game['rounds'] as List<dynamic>? ?? const []))
        _migrateInputHolder(r as Map<String, dynamic>),
    ],
    if (game['pendingRound'] != null)
      'pendingRound': _migrateInputHolder(
        game['pendingRound'] as Map<String, dynamic>,
      ),
  };

  /// Replaces the `input` field of a round / pending round with the v3 form.
  static Map<String, dynamic> _migrateInputHolder(Map<String, dynamic> holder) {
    final gameId = holder['gameId'] as String;
    final input = (holder['input'] as Map<String, dynamic>?) ?? const {};
    return {
      ...holder,
      'input': {'counts': _toCountsList(gameId, input)},
    };
  }

  static List<Map<String, int>> _toCountsList(
    String gameId,
    Map<String, dynamic> input,
  ) {
    final entry = _schema[gameId];
    if (entry == null) return const [];
    final (shape, keys) = entry;
    switch (shape) {
      case _Shape.counts:
        final map = (input[keys[0]] as Map?)?.cast<String, int>() ?? const {};
        return [Map<String, int>.from(map)];
      case _Shape.single:
        final id = input[keys[0]] as String?;
        return [
          id == null ? <String, int>{} : {id: 1},
        ];
      case _Shape.dual:
        final id1 = input[keys[0]] as String?;
        final id2 = input[keys[1]] as String?;
        return [
          id1 == null ? <String, int>{} : {id1: 1},
          id2 == null ? <String, int>{} : {id2: 1},
        ];
    }
  }
}

// =============================================================================
// v3 → v4 : doublesJson {pairs:{…}, initiators:{…}}
//         → doublesJson {"A,B": {state:…, initiator:…}}
// =============================================================================

class _V3ToV4 extends StorageMigration {
  const _V3ToV4();

  @override
  int get fromVersion => 3;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _migrateGame(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _migrateGame(Map<String, dynamic> game) => {
    ...game,
    'rounds': [
      for (final r in (game['rounds'] as List<dynamic>? ?? const []))
        _migrateHolder(r as Map<String, dynamic>),
    ],
    if (game['pendingRound'] != null)
      'pendingRound': _migrateHolder(
        game['pendingRound'] as Map<String, dynamic>,
      ),
  };

  static Map<String, dynamic> _migrateHolder(Map<String, dynamic> h) {
    final raw = h['doublesJson'] as Map<String, dynamic>?;
    if (raw == null) return h;
    return {...h, 'doublesJson': _reshape(raw)};
  }

  /// Reshape { pairs: {"A,B": state}, initiators: {"A,B": uuid} }
  ///      to { "A,B": { state: …, initiator: … } }
  static Map<String, dynamic> _reshape(Map<String, dynamic> old) {
    final pairs = (old['pairs'] as Map<String, dynamic>?) ?? {};
    final inits = (old['initiators'] as Map<String, dynamic>?) ?? {};
    return {
      for (final e in pairs.entries)
        e.key: <String, dynamic>{'state': e.value, 'initiator': inits[e.key]},
    };
  }
}

// =============================================================================
// v4 → v5: add starterVariant (defaults to 'dealerStarts')
//          add heartsVariant (defaults to 'onlyAfterPlayedHeart')
// =============================================================================

class _V4ToV5 extends StorageMigration {
  const _V4ToV5();

  @override
  int get fromVersion => 4;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games)
      <String, dynamic>{
        ...(raw as Map<String, dynamic>),
        'starterVariant': 'dealerStarts',
        'heartsVariant': 'onlyAfterPlayedHeart',
      },
  ];
}

// =============================================================================
// v5 → v6: group the two top-level rule-variant keys under one `ruleVariants`
//          map, so future rule variants stay grouped instead of cluttering the
//          game root.
//          { starterVariant, heartsVariant } → { ruleVariants: { … } }
// =============================================================================
//
// v5 always carried both keys at the game root (the _V4ToV5 step injects them
// and the v5-era writer emitted them). This step moves them verbatim into a
// nested map and drops the old keys; absent values fall back to the v5 defaults
// this step was frozen against.

class _V5ToV6 extends StorageMigration {
  const _V5ToV6();

  @override
  int get fromVersion => 5;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _migrateGame(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _migrateGame(Map<String, dynamic> game) {
    return <String, dynamic>{
      for (final e in game.entries)
        if (e.key != 'starterVariant' && e.key != 'heartsVariant')
          e.key: e.value,
      'ruleVariants': <String, dynamic>{
        'starterVariant': game['starterVariant'] ?? 'dealerStarts',
        'heartsVariant': game['heartsVariant'] ?? 'onlyAfterPlayedHeart',
      },
    };
  }
}

// =============================================================================
// v6 → v7: normalise JS negative-zero in persisted round scores
// =============================================================================
//
// On dart2js, `0 * negative_int` produces JavaScript negative-zero (-0).
// In release mode Dart skips runtime type checks, so double(-0.0) could slip
// through an `int`-typed map and survive JSON serialisation as -0.0. This step
// rewrites any such value to a plain 0, so no future reader ever sees -0.0 in
// stored scores. The source bug is fixed in MiniGame.calculateScores (v7+
// builds never write -0.0); this migration repairs data written before that fix.

class _V6ToV7 extends StorageMigration {
  const _V6ToV7();

  @override
  int get fromVersion => 6;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _migrateGame(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _migrateGame(Map<String, dynamic> game) => {
    ...game,
    'rounds': [
      for (final r in (game['rounds'] as List<dynamic>? ?? const []))
        _migrateRound(r as Map<String, dynamic>),
    ],
  };

  static Map<String, dynamic> _migrateRound(Map<String, dynamic> round) {
    final scores = round['scores'] as Map<String, dynamic>?;
    if (scores == null) return round;
    // (-0.0) == 0 is true in both Dart and JS, so the comparison catches
    // negative-zero; returning the literal 0 avoids toInt() which would
    // preserve -0 in dart2js.
    return {
      ...round,
      'scores': {
        for (final e in scores.entries)
          e.key: (e.value as num) == 0 ? 0 : (e.value as num).toInt(),
      },
    };
  }
}

// =============================================================================
// v7 → v8: add the optional `gameName` field to GameSession (no data change)
// =============================================================================
//
// v8 introduces an optional, user-supplied `gameName` on a session. It is
// serialized only when set (omit-when-null, like `pendingRound` / `doublesJson`),
// so a v7 game — which never had a name — is already a valid v8 game with no
// name. There is genuinely nothing to transform; this step exists solely to
// advance the version so an older v7-only build refuses to silently drop a name
// written by a newer build (it hits version > currentStorageVersion and surfaces
// the "App bijwerken vereist" screen instead).

class _V7ToV8 extends StorageMigration {
  const _V7ToV8();

  @override
  int get fromVersion => 7;

  @override
  List<dynamic> apply(List<dynamic> games) => games;
}

// =============================================================================
// v8 → v9: add `scoredAt` — timestamp of the last committed round
// =============================================================================
//
// v9 introduces `scoredAt`, which advances only when a RoundRecord is
// committed (round appended, replaced, or deleted). For all existing games the
// best approximation is `updatedAt`, so this step copies it verbatim — which is
// why every stored game ends up with a `scoredAt`, and `GameSession.fromJson`
// can require the field (no fallback) without breaking older data.

class _V8ToV9 extends StorageMigration {
  const _V8ToV9();

  @override
  int get fromVersion => 8;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _addScoredAt(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _addScoredAt(Map<String, dynamic> game) => {
    ...game,
    'scoredAt': game['updatedAt'],
  };
}

// =============================================================================
// v9 → v10: replace timestamp game id with UUID v4; strip redundant `gameName`
// =============================================================================
//
// Two changes bundled in one step:
//
// 1. Game `id` was previously a microseconds-since-epoch string. Each stored
//    game gets a fresh UUID v4, making ids consistent with player ids and
//    satisfying the UUID v4 check added to `validateGameSession`.
//
// 2. `gameName` was written alongside `gameId` in every round and pending round
//    as a human-readable label, but was never read back — all loading paths look
//    up the game exclusively by `gameId`. This step strips the dead field so
//    stored data stays lean and the model stays the canonical source of names.

class _V9ToV10 extends StorageMigration {
  const _V9ToV10();

  @override
  int get fromVersion => 9;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _migrateGame(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _migrateGame(Map<String, dynamic> game) => {
    ...game,
    'id': _uuid.v4(),
    'rounds': [
      for (final r in (game['rounds'] as List<dynamic>? ?? const []))
        _dropGameName(r as Map<String, dynamic>),
    ],
    if (game['pendingRound'] != null)
      'pendingRound': _dropGameName(
        game['pendingRound'] as Map<String, dynamic>,
      ),
  };

  static Map<String, dynamic> _dropGameName(Map<String, dynamic> holder) => {
    for (final e in holder.entries)
      if (e.key != 'gameName') e.key: e.value,
  };
}

// =============================================================================
// v10 → v11: normalize stored player + game names
// =============================================================================
//
// The import/write validation gate now REJECTS un-normalized names: a player
// name with leading/trailing whitespace, or a gameName that isn't its trimmed,
// non-empty form. The create/edit UI always trimmed before saving, so stored
// names are already normalized in practice — but a stray space could have
// slipped through historically (or via a hand-edited backup imported before the
// gate existed). This step trims every player name and normalizes every
// gameName (trim; drop to null when empty), so all stored data conforms to the
// invariant the gate enforces and an export→import round-trip can't be rejected
// by the freshly-strict gate.
//
// Self-contained: the normalization is inlined (`String.trim`) rather than
// calling `game_constraints`, so this frozen step keeps working unchanged.

class _V10ToV11 extends StorageMigration {
  const _V10ToV11();

  @override
  int get fromVersion => 10;

  @override
  List<dynamic> apply(List<dynamic> games) => [
    for (final raw in games) _migrateGame(raw as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _migrateGame(Map<String, dynamic> game) {
    final result = {
      ...game,
      'players': [
        for (final p in game['players'] as List<dynamic>)
          {...p as Map<String, dynamic>, 'name': (p['name'] as String).trim()},
      ],
    };
    final rawName = game['gameName'];
    if (rawName is String) {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty) {
        result.remove('gameName');
      } else {
        result['gameName'] = trimmed;
      }
    }
    return result;
  }
}
