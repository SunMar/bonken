import 'mini_game.dart';

/// Derives the dealer seat index from the chooser seat index.
///
/// Current rule: dealer = chooser − 1 (the player who dealt sits to the right
/// of the chooser). When configurable game rules are added in the future,
/// this function is the single place to update — nothing else in the codebase
/// should hardcode this relationship.
int dealerIndexFor(int chooserIndex) =>
    (chooserIndex - 1 + playerCount) % playerCount;

/// Derives the starter seat index from the chooser seat index.
///
/// Current rule: starter = dealer (same seat). A future rule variant will
/// allow the starter to be the player opposite the chooser (starter = chooser − 2).
int starterIndexFor(int chooserIndex) => dealerIndexFor(chooserIndex);

/// Per-chooser game quota: across a whole game each chooser may pick at most
/// this many negative / positive games. A **soft** rule — the UI surfaces it as
/// a disabled tile with a "Toch doorgaan" override (see `game_screen.dart`).
const int maxNegativePerChooser = 2;
const int maxPositivePerChooser = 1;

/// Whether the current chooser has reached their quota for [category], given how
/// many negative/positive games they have already chosen this game.
bool quotaReached(
  GameCategory category, {
  required int negativeChosen,
  required int positiveChosen,
}) => switch (category) {
  GameCategory.negative => negativeChosen >= maxNegativePerChooser,
  GameCategory.positive => positiveChosen >= maxPositivePerChooser,
};
