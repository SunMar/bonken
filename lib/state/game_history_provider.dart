import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_session.dart';

final gameHistoryProvider =
    AsyncNotifierProvider<GameHistoryNotifier, List<GameSession>>(
      GameHistoryNotifier.new,
    );

class GameHistoryNotifier extends AsyncNotifier<List<GameSession>> {
  static const _storageKey = 'bonken_game_history';

  @override
  Future<List<GameSession>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final sessions = [
        for (final item in list)
          GameSession.fromJson(item as Map<String, dynamic>),
      ];
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      // Corrupt data — start fresh.
      return [];
    }
  }

  /// Saves or updates a session.
  ///
  /// If a session with the same [GameSession.id] already exists it is replaced
  /// in place (preserving its position in the list).  Otherwise the new session
  /// is inserted at the front (newest first).
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
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> deleteGame(String id) async {
    final current = await future;
    final updated = current.where((g) => g.id != id).toList();
    state = AsyncValue.data(updated);
    await _persist(updated);
  }

  Future<void> _persist(List<GameSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode([for (final s in sessions) s.toJson()]),
    );
  }

  /// All unique player names that have appeared across all saved sessions,
  /// sorted by how often they appear (most frequent first).
  ///
  /// Returns an empty list while the history is still loading.
  List<String> get playerNameSuggestions {
    final sessions = state.value;
    if (sessions == null || sessions.isEmpty) return [];
    final counts = <String, int>{};
    for (final session in sessions) {
      for (final name in session.playerNames) {
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
  }
}
