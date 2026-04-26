import '../mini_game.dart';
import 'negative_games.dart';
import 'positive_games.dart';

/// The complete ordered list of all 13 Bonken mini-games.
///
/// Order matches the conventional play order:
///   Positive games first (any order among them), then negative games.
///   This list is the single source of truth for the game catalog.
const List<MiniGame> allGames = [
  // Positive (5)
  Clubs(),
  Diamonds(),
  Hearts(),
  Spades(),
  NoTrump(),
  // Negative (8)
  KingOfHearts(),
  KingsAndJacks(),
  Queens(),
  Duck(),
  HeartPoints(),
  SeventhAndThirteenth(),
  FinalTrick(),
  Dominoes(),
];
