import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_session.dart';
import '../models/games/game_catalog.dart';
import '../models/input_descriptor.dart';
import '../models/player.dart';

class UnsupportedStorageVersionException implements Exception {
  const UnsupportedStorageVersionException(this.version);
  final int version;

  @override
  String toString() =>
      'Game history was written by a newer version of the app (v$version). '
      'Please update the app.';
}

final gameHistoryProvider =
    AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>(
      GameHistoryNotifier.new,
    );

class GameHistoryNotifier extends AsyncNotifier<List<GameSession>> {
  static const _storageKey = 'game_history';
  static const _legacyStorageKey = 'bonken_game_history';
  static const _currentVersion = 2;

  /// Cached result of [playerNameSuggestions]. Recomputed lazily on the
  /// next read after any mutation (save / delete / reload).
  List<String>? _suggestionsCache;

  @override
  Future<List<GameSession>> build() async {
    _suggestionsCache = null;
    final prefs = await SharedPreferences.getInstance();
    try {
      List<dynamic> games;
      final currentRaw = prefs.getString(_storageKey);
      if (currentRaw != null) {
        final decoded = jsonDecode(currentRaw) as Map<String, dynamic>;
        final version = decoded['version'] as int;
        if (version > _currentVersion) {
          throw UnsupportedStorageVersionException(version);
        }
        games = decoded['games'] as List<dynamic>;
        if (version < _currentVersion) {
          // version 1 in versioned storage — shouldn't exist in practice
          // (v1 was the legacy unversioned array), but migrate defensively.
          games = _migrateV1ToV2(games);
          await prefs.setString(
            _storageKey,
            jsonEncode({'version': _currentVersion, 'games': games}),
          );
        }
      } else {
        final legacyRaw = prefs.getString(_legacyStorageKey);
        if (legacyRaw == null) return [];
        // Legacy key is always v1 (raw JSON array). Migrate to v2, write to
        // the current key, and remove the legacy key.
        games = _migrateV1ToV2(jsonDecode(legacyRaw) as List<dynamic>);
        await prefs.setString(
          _storageKey,
          jsonEncode({'version': _currentVersion, 'games': games}),
        );
        await prefs.remove(_legacyStorageKey);
      }
      final sessions = [
        for (final item in games)
          GameSession.fromJson(item as Map<String, dynamic>),
      ];
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (e) {
      if (e is UnsupportedStorageVersionException) rethrow;
      // Corrupt data — start fresh.
      return [];
    }
  }

  /// Saves or updates a session.
  ///
  /// If a session with the same [GameSession.id] already exists it is replaced
  /// in place. Otherwise the new session is inserted at the front (newest first).
  Future<void> saveGame(GameSession session) async {
    final current = await future;
    final idx = current.indexWhere((g) => g.id == session.id);
    final updated = List<GameSession>.from(current);
    if (idx >= 0) {
      updated[idx] = session;
    } else {
      updated.add(session);
    }
    updated.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _suggestionsCache = null;
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _suggestionsCache = null;
    state = const AsyncValue.data([]);
  }

  Future<void> deleteGame(String id) async {
    final current = await future;
    final updated = current.where((g) => g.id != id).toList();
    _suggestionsCache = null;
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> _persist(List<GameSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'version': _currentVersion,
        'games': [for (final s in sessions) s.toJson()],
      }),
    );
  }

  /// All unique player names that have appeared across all saved sessions,
  /// sorted by how often they appear (most frequent first); ties are broken
  /// alphabetically (case-insensitive).
  List<String> get playerNameSuggestions {
    final cached = _suggestionsCache;
    if (cached != null) return cached;
    final sessions = state.value;
    if (sessions == null || sessions.isEmpty) {
      return _suggestionsCache = const [];
    }
    final counts = <String, int>{};
    for (final session in sessions) {
      for (final p in session.players) {
        counts[p.name] = (counts[p.name] ?? 0) + 1;
      }
    }
    final result = counts.keys.toList()
      ..sort((a, b) => _compareByFrequencyThenName(a, b, counts));
    return _suggestionsCache = List.unmodifiable(result);
  }

  static int _compareByFrequencyThenName(
    String a,
    String b,
    Map<String, int> counts,
  ) {
    final byFrequency = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
    if (byFrequency != 0) return byFrequency;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  // ---------------------------------------------------------------------------
  // Migration
  // ---------------------------------------------------------------------------

  /// Converts a v1 (raw JSON array) game list to v2 format in memory.
  ///
  /// v1 stored:
  ///   • playerNames: `List` of String (no UUIDs)
  ///   • rounds[].dealerIndex + chooserIndex (ints)
  ///   • rounds[].scores: {"0": v, "1": v, ...} (index-keyed)
  ///   • rounds[].input: index-keyed (List of int for counts, int? for single/dual)
  ///   • rounds[].doublesJson: pair keys "a,b" with integer seat indices;
  ///     initiator values are ints
  ///   • pendingRound.dealerIndex + chooserIndex
  ///
  /// v2 stores:
  ///   • players: [{id, name}, ...] (UUIDs generated during migration)
  ///   • firstDealerId (back-computed from history)
  ///   • rounds[].chooserId (UUID) — dealerIndex dropped
  ///   • rounds[].scores: {uuid: v} (ID-keyed)
  ///   • rounds[].input: UUID-keyed (Map of String to int for counts, String? UUID
  ///     for single/dual)
  ///   • rounds[].doublesJson: pair keys "uuidA,uuidB"; initiator values
  ///     UUID strings
  ///   • pendingRound.chooserId — dealerIndex dropped
  static List<dynamic> _migrateV1ToV2(List<dynamic> v1Games) {
    final v2Games = <Map<String, dynamic>>[];
    for (final raw in v1Games) {
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
      //   • If a pending round exists, its dealerIndex is the current dealer
      //     for round (rounds.length + 1). So:
      //       firstDealerIdx = (pendingDealerIdx - rounds.length) mod 4
      //   • Otherwise use the last completed round's dealer:
      //       lastDealerIdx dealt round rounds.length, so
      //       firstDealerIdx = (lastDealerIdx - rounds.length + 1) mod 4
      //   • If no rounds at all, default to 0.
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

      // Migrate each round.
      final v2Rounds = <Map<String, dynamic>>[];
      for (final r in rounds) {
        final round = r as Map<String, dynamic>;
        final chooserIdx = (round['chooserIndex'] as int?) ?? 0;
        final chooserId = players[chooserIdx.clamp(0, 3)].id;

        // v1 scores: {"0": v, "1": v, ...} — keys are stringified ints.
        final v1Scores = round['scores'] as Map<String, dynamic>? ?? {};
        final v2Scores = <String, dynamic>{
          for (final e in v1Scores.entries)
            players[int.tryParse(e.key)?.clamp(0, 3) ?? 0].id: e.value,
        };

        final gameId = round['gameId'] as String;
        final miniGame = allGames.where((g) => g.id == gameId).firstOrNull;
        final inputRaw = (round['input'] as Map<String, dynamic>?) ?? {};
        final doublesRaw = round['doublesJson'] as Map<String, dynamic>?;

        v2Rounds.add({
          'roundNumber': round['roundNumber'],
          'gameName': round['gameName'],
          'gameId': gameId,
          'chooserId': chooserId,
          'scores': v2Scores,
          'input': miniGame != null
              ? _migrateInputV1ToV2(
                  inputRaw,
                  miniGame.inputDescriptor,
                  playerIds,
                )
              : inputRaw,
          if (doublesRaw != null)
            'doublesJson': _migrateDoublesV1ToV2(doublesRaw, playerIds),
        });
      }

      // Migrate pending round.
      Map<String, dynamic>? v2Pending;
      if (pendingRaw != null) {
        final chooserIdx = (pendingRaw['chooserIndex'] as int?) ?? 0;
        final chooserId = players[chooserIdx.clamp(0, 3)].id;
        final gameId = pendingRaw['gameId'] as String;
        final miniGame = allGames.where((g) => g.id == gameId).firstOrNull;
        final inputRaw = (pendingRaw['input'] as Map<String, dynamic>?) ?? {};
        final doublesRaw = pendingRaw['doublesJson'] as Map<String, dynamic>?;
        v2Pending = {
          'gameId': gameId,
          'gameName': pendingRaw['gameName'],
          'chooserId': chooserId,
          'input': miniGame != null
              ? _migrateInputV1ToV2(
                  inputRaw,
                  miniGame.inputDescriptor,
                  playerIds,
                )
              : inputRaw,
          if (doublesRaw != null)
            'doublesJson': _migrateDoublesV1ToV2(doublesRaw, playerIds),
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

  static Map<String, dynamic> _migrateInputV1ToV2(
    Map<String, dynamic> input,
    InputDescriptor descriptor,
    List<String> playerIds,
  ) {
    String pid(int idx) => playerIds[idx.clamp(0, playerIds.length - 1)];
    return switch (descriptor) {
      CountsInputDescriptor d => () {
        final list = (input[d.inputKey] as List?)?.cast<int>();
        if (list == null) return input;
        return {
          d.inputKey: {
            for (int i = 0; i < playerIds.length; i++) playerIds[i]: list[i],
          },
        };
      }(),
      SinglePlayerInputDescriptor d => () {
        final idx = input[d.inputKey] as int?;
        return {d.inputKey: idx == null ? null : pid(idx)};
      }(),
      DualPlayerInputDescriptor d => () {
        final idx1 = input[d.inputKey1] as int?;
        final idx2 = input[d.inputKey2] as int?;
        return {
          d.inputKey1: idx1 == null ? null : pid(idx1),
          d.inputKey2: idx2 == null ? null : pid(idx2),
        };
      }(),
    };
  }

  static Map<String, dynamic> _migrateDoublesV1ToV2(
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
