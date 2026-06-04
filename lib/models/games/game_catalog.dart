import '../mini_game.dart';
import 'negative_games.dart';
import 'positive_games.dart';

/// The complete list of all 13 Bonken mini-games.
///
/// Negative games are listed first, then positive games, matching the
/// display order used throughout the UI.
/// This list is the single source of truth for the game catalog.
const List<MiniGame> allGames = [
  // Negative (8)
  KingOfHearts(),
  KingsAndJacks(),
  Queens(),
  Duck(),
  HeartPoints(),
  SeventhAndThirteenth(),
  FinalTrick(),
  Dominoes(),
  // Positive (5)
  Clubs(),
  Diamonds(),
  Hearts(),
  Spades(),
  NoTrump(),
];

/// Returns the [MiniGame] whose [MiniGame.id] matches [gameId].
///
/// Throws a [StateError] with a descriptive message on an unknown id. An
/// unknown id during JSON deserialization is caught by the `on Object` boundary
/// in `GameHistoryNotifier.build()` and surfaces as a [CorruptStorageException].
/// An unknown id after a successful load is a programming error — the throw
/// makes it loud rather than silently loading the wrong game.
MiniGame gameById(String gameId) => allGames.firstWhere(
  (g) => g.id == gameId,
  orElse: () => throw StateError('Unknown game id: $gameId'),
);
