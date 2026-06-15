/// Single source of truth for "what counts as valid game data" — the rules for
/// player names and game names, shared by every layer that touches them:
/// the scoring-engine invariants ([assertGameInvariants]), the import/write
/// validation gate ([validation.dart]), and the create/edit UI.
///
/// **Pure Dart, no Flutter imports**, so it can live in the models layer and be
/// referenced from anywhere above it (models → state → UI), never the reverse.
///
/// Designed predicate-first: the boolean/normalizer functions here are the one
/// place the rule logic lives. Throwing validators (`validation.dart`,
/// `game_invariants.dart`) are thin wrappers that call these and add their own
/// error type + message; the UI calls the predicates directly for live feedback.
library;

/// Maximum number of characters allowed in a player name.
const int kPlayerNameMaxLength = 20;

/// Maximum number of characters allowed in a game name.
const int kGameNameMaxLength = 50;

/// Canonical normalization for a player name: strip surrounding whitespace.
String normalizePlayerName(String raw) => raw.trim();

/// Canonical normalization for an optional game name. A null, empty, or
/// whitespace-only input normalizes to `null` (the stored "no name" form);
/// otherwise the trimmed value is returned.
String? normalizeGameName(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// True when [name] fits within the player-name length limit (after trim).
bool playerNameLengthValid(String name) =>
    normalizePlayerName(name).length <= kPlayerNameMaxLength;

/// True when [name] fits within the game-name length limit (after trim).
bool gameNameLengthValid(String name) =>
    name.trim().length <= kGameNameMaxLength;

/// True when every name in [names] is non-empty after trimming.
bool allPlayerNamesFilled(List<String> names) =>
    names.every((n) => normalizePlayerName(n).isNotEmpty);

/// Indices of player names that collide case-insensitively with another
/// non-empty name in [names]. Empty / whitespace-only names are ignored.
///
/// This is the single definition of player-name uniqueness — used by the
/// engine invariants, the validation gate, and the create/edit UI alike.
Set<int> duplicatePlayerNameIndices(List<String> names) {
  final byKey = <String, List<int>>{};
  for (var i = 0; i < names.length; i++) {
    final key = normalizePlayerName(names[i]).toLowerCase();
    if (key.isEmpty) continue;
    byKey.putIfAbsent(key, () => []).add(i);
  }
  return {
    for (final indices in byKey.values)
      if (indices.length > 1) ...indices,
  };
}

/// True when [names] contains at least one case-insensitive duplicate among
/// its non-empty entries.
bool hasDuplicatePlayerNames(List<String> names) =>
    duplicatePlayerNameIndices(names).isNotEmpty;
