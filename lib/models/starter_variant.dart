import 'game_mechanics.dart';
import 'mini_game.dart';

const String kStarterVariantSectionTitle = 'Uitkomst';
const String kStarterVariantSectionSubtitle =
    'Welke speler komt uit in de eerste slag?';

/// Which player leads the first trick of a round (speelt de eerste kaart).
enum StarterVariant {
  dealerStarts,
  oppositeChooserStarts;

  String get label => switch (this) {
    StarterVariant.dealerStarts => 'Deler',
    StarterVariant.oppositeChooserStarts => 'Tegenover de kiezer',
  };

  String get description => switch (this) {
    StarterVariant.dealerStarts => 'De deler komt uit in de eerste slag.',
    StarterVariant.oppositeChooserStarts =>
      'De speler tegenover de kiezer komt uit in de eerste slag.',
  };
}

/// Derives the starter seat index from the chooser seat index and the active
/// [StarterVariant].
int starterIndexFor(int chooserIndex, StarterVariant variant) =>
    switch (variant) {
      StarterVariant.dealerStarts => dealerIndexFor(chooserIndex),
      StarterVariant.oppositeChooserStarts =>
        (chooserIndex - 2 + playerCount) % playerCount,
    };
