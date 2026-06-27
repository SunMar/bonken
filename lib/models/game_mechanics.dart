import 'mini_game.dart';
import 'starter_variant.dart';

/// Derives the dealer seat index from the chooser seat index.
///
/// Rule: dealer = chooser − 1 (the player who dealt sits to the right of the
/// chooser).
int dealerIndexFor(int chooserIndex) =>
    (chooserIndex - 1 + playerCount) % playerCount;

/// Derives the default chooser seat index from the [dealerIndex].
///
/// Rule: chooser = dealer + 1 (the chooser sits to the left of the dealer) —
/// the algebraic inverse of [dealerIndexFor]. The `+ playerCount` term mirrors
/// [dealerIndexFor]'s defensive normalization even though `+ 1` can never go
/// negative, so both directions read identically.
int chooserIndexFor(int dealerIndex) =>
    (dealerIndex + 1 + playerCount) % playerCount;

/// Position of [player] in the doubling turn order for a round chosen by
/// [chooserIndex]: `0` is the first to double (the player to the left of
/// the chooser, i.e. `(chooserIndex + 1) % 4`) and `3` is the chooser
/// themselves, who doubles last.
///
/// The same index drives both the input list ordering in `DoublesPicker`
/// and the chip ordering in `DoublesChips`, so they always agree.
int doublingTurnIndex(int player, int chooserIndex) =>
    (player - chooserIndex - 1 + playerCount) % playerCount;

/// Derives the starter seat index from the chooser seat index and the active
/// [StarterVariant].
///
/// The starter is the player who leads the first trick of the round. Every seat
/// relationship lives here so this file remains the single home for all seat
/// arithmetic (see ARCHITECTURE.md §2 / §5).
int starterIndexFor(int chooserIndex, StarterVariant variant) =>
    switch (variant) {
      .dealerStarts => dealerIndexFor(chooserIndex),
      .oppositeChooserStarts => (chooserIndex - 2 + playerCount) % playerCount,
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
  .negative => negativeChosen >= maxNegativePerChooser,
  .positive => positiveChosen >= maxPositivePerChooser,
};
