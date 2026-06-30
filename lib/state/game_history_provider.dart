import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_constraints.dart';
import '../models/game_session.dart';
import 'migrations.dart';
import 'save_health_provider.dart';
import 'storage_exceptions.dart';
import 'validation.dart';

final gameHistoryProvider =
    AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>(
      GameHistoryNotifier.new,
    );

class GameHistoryNotifier extends AsyncNotifier<List<GameSession>> {
  static const storageKey = 'game_history';
  static const _legacyStorageKey = 'bonken_game_history';

  @override
  Future<List<GameSession>> build() async {
    final prefs = SharedPreferencesAsync();
    try {
      List<dynamic> games;
      final currentRaw = await prefs.getString(storageKey);
      if (currentRaw != null) {
        final decoded = jsonDecode(currentRaw) as Map<String, dynamic>;
        final version = decoded['version'] as int;
        if (version > currentStorageVersion) {
          throw UnsupportedVersionException(version);
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
        final legacyRaw = await prefs.getString(_legacyStorageKey);
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
      sessions.sort(_byScoredAtThenId);
      return sessions;
    } on UnsupportedVersionException {
      rethrow;
    } on Object catch (e) {
      // Unreadable storage — surface it (mirrors the unsupported-version flow)
      // instead of silently discarding the user's saved games. Catching `Object`
      // is deliberate: corrupt data manifests as both `FormatException` (from
      // `jsonDecode`) and `TypeError` (from `as` casts in fromJson / migration).
      throw CorruptPersistenceException(e);
    }
  }

  /// Saves or updates a session.
  ///
  /// If a session with the same [GameSession.id] already exists it is replaced
  /// in place. Otherwise the new session is inserted at the front (newest first).
  Future<void> saveGame(GameSession session) async {
    validateGameSession(session);
    final current = await future;
    final idx = current.indexWhere((g) => g.id == session.id);
    final updated = List<GameSession>.from(current);
    if (idx >= 0) {
      updated[idx] = session;
    } else {
      updated.add(session);
    }
    updated.sort(_byScoredAtThenId);
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  /// Clears all saved games. Writes the canonical empty `{version, games:[]}`
  /// envelope (like [replaceAll]) rather than removing the key, and drops any
  /// stale legacy blob, so a cleared history is never re-promoted from the
  /// legacy key on the next cold start.
  Future<void> clearHistory() async {
    final prefs = SharedPreferencesAsync();
    await prefs.remove(_legacyStorageKey);
    state = const AsyncValue.data([]);
    await _persist(const []);
  }

  /// Replaces the entire game history with [sessions].
  ///
  /// Called exclusively by the import path after both streams have been
  /// validated (ARCHITECTURE.md §9). Serialises the `{version, games}` envelope,
  /// writes it under [storageKey], and updates state — so the storage shape
  /// stays owned here (never duplicated in the import code, ARCH §2).
  Future<void> replaceAll(List<GameSession> sessions) async {
    final sorted = List<GameSession>.from(sessions)..sort(_byScoredAtThenId);
    state = AsyncValue.data(sorted);
    await _persist(sorted, surfaceFault: true);
  }

  Future<void> deleteGame(String id) async {
    final current = await future;
    final updated = current.where((g) => g.id != id).toList();
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  /// Re-persists the in-memory history to retry after a write fault — e.g. the
  /// app regained focus after the user freed up storage. A success clears the
  /// save-error banner (`saveHealthyProvider`); a still-failing write keeps it.
  /// No-op while history is loading or in an error state.
  Future<void> retryPersist() async {
    if (state.hasValue) await _persist(state.requireValue);
  }

  Future<void> _persist(
    List<GameSession> sessions, {
    bool surfaceFault = false,
  }) async {
    // Encode before the write so a `toJson` bug surfaces as the bug it is,
    // instead of being mistaken for a storage fault.
    final json = jsonEncode({
      'version': currentStorageVersion,
      'games': [for (final s in sessions) s.toJson()],
    });
    final health = ref.read(saveHealthyProvider.notifier);
    try {
      await SharedPreferencesAsync().setString(storageKey, json);
      health.markOk();
    } on Exception catch (e) {
      // Environmental write fault (e.g. full disk): in-memory state is intact,
      // so flag the sticky save-error banner and keep working. Only [replaceAll]
      // (the import path) surfaces it, so a deliberate import reports cleanly.
      health.markFailed();
      if (surfaceFault) throw PersistenceWriteException(e);
    }
  }
}

/// Sorts saved games newest-scored first, breaking ties on the (unique) [id] so
/// the order is deterministic even when two sessions share a `scoredAt`
/// millisecond (e.g. two "new game, same players" started in quick succession).
int _byScoredAtThenId(GameSession a, GameSession b) {
  final byScoredAt = b.scoredAt.compareTo(a.scoredAt);
  return byScoredAt != 0 ? byScoredAt : a.id.compareTo(b.id);
}

/// All unique player names across saved sessions, most-frequent first (ties
/// broken alphabetically, case-insensitive). Used by the new-game / edit-game
/// autocomplete.
///
/// Derived from [gameHistoryProvider], so it recomputes only when history
/// actually changes (a mutation or load) — invalidation is structural, not a
/// hand-placed cache reset in every mutator — while reads stay O(1) (Riverpod
/// memoizes until the dependency changes). Empty while history is loading or
/// errored.
final playerNameSuggestionsProvider = Provider<List<String>>((ref) {
  final sessions = ref.watch(gameHistoryProvider).value ?? const [];
  if (sessions.isEmpty) return const [];
  final counts = <String, int>{};
  for (final session in sessions) {
    for (final p in session.players) {
      counts[p.name] = (counts[p.name] ?? 0) + 1;
    }
  }
  final result = counts.keys.toList()
    ..sort((a, b) => _compareByFrequencyThenName(a, b, counts));
  return List<String>.unmodifiable(result);
});

int _compareByFrequencyThenName(String a, String b, Map<String, int> counts) {
  final byFrequency = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
  if (byFrequency != 0) return byFrequency;
  return caseFoldName(a).compareTo(caseFoldName(b));
}
