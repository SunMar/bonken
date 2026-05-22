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
