import 'labeled_variant.dart';

const String kStarterVariantSectionTitle = 'Uitkomst';
const String kStarterVariantSectionSubtitle =
    'Welke speler komt uit in de eerste slag?';

/// Which player leads the first trick of a round (speelt de eerste kaart).
enum StarterVariant implements LabeledVariant {
  dealerStarts,
  oppositeChooserStarts;

  @override
  String get label => switch (this) {
    .dealerStarts => 'Deler',
    .oppositeChooserStarts => 'Tegenover de kiezer',
  };

  @override
  String get description => switch (this) {
    .dealerStarts => 'De deler komt uit in de eerste slag.',
    .oppositeChooserStarts =>
      'De speler tegenover de kiezer komt uit in de eerste slag.',
  };
}
