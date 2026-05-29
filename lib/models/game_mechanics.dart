import 'mini_game.dart';
import 'starter_variant.dart';

/// Derives the dealer seat index from the chooser seat index.
///
/// Rule: dealer = chooser − 1 (the player who dealt sits to the right of the
/// chooser).
int dealerIndexFor(int chooserIndex) =>
    (chooserIndex - 1 + playerCount) % playerCount;

/// Derives the starter seat index from the chooser seat index and the active
/// [StarterVariant].
///
/// The starter is the player who leads the first trick of the round. Both seat
/// relationships live here so this file remains the single home for all seat
/// arithmetic (see ARCHITECTURE.md §2 / §5).
int starterIndexFor(int chooserIndex, StarterVariant variant) =>
    switch (variant) {
      StarterVariant.dealerStarts => dealerIndexFor(chooserIndex),
      StarterVariant.oppositeChooserStarts =>
        (chooserIndex - 2 + playerCount) % playerCount,
    };

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
