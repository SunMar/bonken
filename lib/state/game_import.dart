import 'dart:convert';

import '../models/game_session.dart';

/// Whether two games hold the same data, regardless of how each was built.
///
/// A plain `jsonEncode(a.toJson()) == jsonEncode(b.toJson())` is *not* reliable:
/// some fields are player-UUID-keyed maps (round `scores`, the doubling matrix,
/// input counts) that the model treats as unordered — `DoubleMatrix` and
/// `ScoreResult` compare/hash them order-independently — yet `toJson` serializes
/// them in insertion order. So the *same* game built by two different paths (one
/// decoded from a scanned QR, one replayed/edited in local history) can serialize
/// its maps in a different key order. [_canonical] removes that artifact, so the
/// comparison depends on content alone.
bool sameGameData(GameSession a, GameSession b) =>
    jsonEncode(_canonical(a.toJson())) == jsonEncode(_canonical(b.toJson()));

/// Rewrites a decoded-JSON tree into a canonical form for comparison: every map
/// is rebuilt with its keys **sorted**, while lists keep their order (list
/// position is meaningful here — seat order, round order — and must not be
/// touched). Scalars pass through unchanged. Recurses into nested maps/lists.
Object? _canonical(Object? node) {
  if (node is Map) {
    final sortedKeys = node.keys.cast<String>().toList()..sort();
    return {for (final key in sortedKeys) key: _canonical(node[key])};
  }
  if (node is List) {
    return [for (final element in node) _canonical(element)];
  }
  return node;
}

/// How an incoming (already-validated) game relates to the existing history — the
/// new/identical/conflict decision an importer makes about it (the Home QR scanner
/// today). Keyed by game `id`.
sealed class GameImportDisposition {
  const GameImportDisposition();
}

/// No game with this id exists yet — a fresh import.
final class GameImportNew extends GameImportDisposition {
  const GameImportNew();
}

/// A game with this id exists and its data is identical — nothing to write; open
/// the [existing] one.
final class GameImportIdentical extends GameImportDisposition {
  const GameImportIdentical(this.existing);

  final GameSession existing;
}

/// A game with this id exists but its data differs — importing would overwrite
/// the [existing] one, so the caller must confirm first.
final class GameImportConflict extends GameImportDisposition {
  const GameImportConflict(this.existing);

  final GameSession existing;
}

/// Classifies [incoming] against [history] by id, then by [sameGameData]:
/// new id → [GameImportNew]; same id + same data → [GameImportIdentical]; same id
/// + different data → [GameImportConflict]. Pure; performs no writes.
GameImportDisposition classifyGameImport(
  GameSession incoming,
  List<GameSession> history,
) {
  for (final existing in history) {
    if (existing.id != incoming.id) continue;
    return sameGameData(existing, incoming)
        ? GameImportIdentical(existing)
        : GameImportConflict(existing);
  }
  return const GameImportNew();
}
