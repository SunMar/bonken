import 'game_constraints.dart';
import 'game_session.dart';
import 'input_descriptor.dart';
import 'mini_game.dart';

/// Thrown by [assertGameInvariants] when a game violates a business rule that
/// [GameSession.fromJson] does not enforce — e.g. Σ scores, counts sums, or
/// round-sequence integrity.
class GameInvariantError implements Exception {
  const GameInvariantError(this.message);
  final String message;

  @override
  String toString() => 'GameInvariantError: $message';
}

/// Asserts business invariants for a fully-parsed [GameSession]:
/// - Exactly [playerCount] players; no duplicate player IDs or names.
/// - `rounds.length` ≤ [GameSession.totalRounds]; round numbers are a
///   gapless 1..n sequence.
/// - Per completed round: exactly [playerCount] score entries; Σ scores ==
///   `round.game.totalPoints`; for counts games Σ input counts == `game.total`;
///   for recipient games all slots are filled.
///
/// These are the invariants the scoring engine checks with debug-only `assert`s
/// (ARCH §6) that are compiled out in release — exactly where a corrupt backup
/// could otherwise slip through. This function is called (throwing) by the
/// import path and (asserting) by the engine, so the logic lives once.
///
/// Does NOT re-check what [GameSession.fromJson] already validates (id
/// references, game-catalog membership, timestamp parsing, type casts).
void assertGameInvariants(GameSession game) {
  // ── Player constraints ────────────────────────────────────────────────────

  if (game.players.length != playerCount) {
    throw GameInvariantError(
      'Game ${game.id}: expected $playerCount players, '
      'got ${game.players.length}.',
    );
  }

  final playerIds = <String>{};
  for (final p in game.players) {
    if (!playerIds.add(p.id)) {
      throw GameInvariantError(
        'Game ${game.id}: duplicate player id "${p.id}".',
      );
    }
  }

  // Name uniqueness uses the shared, case-insensitive + trimmed rule so the
  // engine assert never drifts from the import/UI definition.
  final names = [for (final p in game.players) p.name];
  final dupNames = duplicatePlayerNameIndices(names);
  if (dupNames.isNotEmpty) {
    throw GameInvariantError(
      'Game ${game.id}: duplicate player name '
      '"${normalizePlayerName(names[dupNames.first])}".',
    );
  }

  // ── Round-sequence constraints ────────────────────────────────────────────

  if (game.rounds.length > GameSession.totalRounds) {
    throw GameInvariantError(
      'Game ${game.id}: ${game.rounds.length} rounds exceed the max '
      '(${GameSession.totalRounds}).',
    );
  }

  for (int i = 0; i < game.rounds.length; i++) {
    final expected = i + 1;
    final actual = game.rounds[i].roundNumber;
    if (actual != expected) {
      throw GameInvariantError(
        'Game ${game.id}: round at index $i has roundNumber $actual, '
        'expected $expected (no gaps or duplicates allowed).',
      );
    }
  }

  // ── Per-round business invariants ─────────────────────────────────────────

  for (final round in game.rounds) {
    final n = round.roundNumber;

    // Exactly 4 score entries.
    if (round.scoresByPlayer.length != playerCount) {
      throw GameInvariantError(
        'Game ${game.id} round $n: ${round.scoresByPlayer.length} score '
        'entries, expected $playerCount.',
      );
    }

    // Σ scores == totalPoints.
    final scoreSum = round.scoresByPlayer.values.fold<int>(0, (a, b) => a + b);
    if (scoreSum != round.game.totalPoints) {
      throw GameInvariantError(
        'Game ${game.id} round $n (${round.game.id}): score sum $scoreSum '
        '!= totalPoints ${round.game.totalPoints}.',
      );
    }

    // Counts game: Σ input counts == game.total.
    if (round.game is CountsMiniGame) {
      final cg = round.game as CountsMiniGame;
      final ci = round.input as CountsInput;
      final countSum = ci.counts.values.fold<int>(0, (a, b) => a + b);
      if (countSum != cg.total) {
        throw GameInvariantError(
          'Game ${game.id} round $n (${cg.id}): counts sum $countSum '
          '!= total ${cg.total}.',
        );
      }
    }

    // Recipient game: all slots must be filled in a completed round.
    if (round.game is RecipientMiniGame) {
      final ri = round.input as RecipientInput;
      for (int s = 0; s < ri.recipients.length; s++) {
        if (ri.recipients[s] == null) {
          throw GameInvariantError(
            'Game ${game.id} round $n (${round.game.id}): recipient '
            'slot $s is null in a completed round.',
          );
        }
      }
    }
  }
}
