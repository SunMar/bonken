import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_session.dart';
import 'migrations.dart';

class UnsupportedStorageVersionException implements Exception {
  const UnsupportedStorageVersionException(this.version);
  final int version;

  @override
  String toString() =>
      'Game history was written by a newer version of the app (v$version). '
      'Please update the app.';
}

/// Raised when the stored game history can't be read (corrupt JSON, malformed
/// structure, …). Surfaced to the UI instead of silently discarding the user's
/// saved games — they see a "Geschiedenis beschadigd" screen with a clear
/// button and can decide.
class CorruptStorageException implements Exception {
  const CorruptStorageException(this.cause);
  final Object cause;

  @override
  String toString() => 'Game history is corrupt and could not be read: $cause';
}

final gameHistoryProvider =
    AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>(
      GameHistoryNotifier.new,
    );

class GameHistoryNotifier extends AsyncNotifier<List<GameSession>> {
  static const storageKey = 'game_history';
  static const _legacyStorageKey = 'bonken_game_history';

  /// Cached result of [playerNameSuggestions]. Recomputed lazily on the
  /// next read after any mutation (save / delete / reload).
  List<String>? _suggestionsCache;

  @override
  Future<List<GameSession>> build() async {
    _suggestionsCache = null;
    final prefs = await SharedPreferences.getInstance();
    try {
      List<dynamic> games;
      final currentRaw = prefs.getString(storageKey);
      if (currentRaw != null) {
        final decoded = jsonDecode(currentRaw) as Map<String, dynamic>;
        final version = decoded['version'] as int;
        if (version > currentStorageVersion) {
          throw UnsupportedStorageVersionException(version);
        }
        games = decoded['games'] as List<dynamic>;
        if (version < currentStorageVersion) {
          games = runStorageMigrations(games, fromVersion: version);
          await prefs.setString(
            storageKey,
            jsonEncode({'version': currentStorageVersion, 'games': games}),
          );
        }
      } else {
        final legacyRaw = prefs.getString(_legacyStorageKey);
        if (legacyRaw == null) return [];
        // Legacy key is the unversioned v1 array — run the full chain from v1.
        games = runStorageMigrations(
          jsonDecode(legacyRaw) as List<dynamic>,
          fromVersion: 1,
        );
        await prefs.setString(
          storageKey,
          jsonEncode({'version': currentStorageVersion, 'games': games}),
        );
        await prefs.remove(_legacyStorageKey);
      }
      final sessions = [
        for (final item in games)
          GameSession.fromJson(item as Map<String, dynamic>),
      ];
      sessions.sort((a, b) => b.scoredAt.compareTo(a.scoredAt));
      return sessions;
    } on UnsupportedStorageVersionException {
      rethrow;
    } on Object catch (e) {
      // Unreadable storage — surface it (mirrors the unsupported-version flow)
      // instead of silently discarding the user's saved games. Catching `Object`
      // is deliberate: corrupt data manifests as both `FormatException` (from
      // `jsonDecode`) and `TypeError` (from `as` casts in fromJson / migration).
      throw CorruptStorageException(e);
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
    updated.sort((a, b) => b.scoredAt.compareTo(a.scoredAt));
    _suggestionsCache = null;
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
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
      storageKey,
      jsonEncode({
        'version': currentStorageVersion,
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
}
