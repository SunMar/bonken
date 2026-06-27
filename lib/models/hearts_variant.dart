import 'labeled_variant.dart';

const String kHeartsVariantSectionTitle = 'Extra spelregel HH/HP';
const String kHeartsVariantSectionSubtitle =
    'Welke extra spelregel geldt voor Harten Heer en Hartenpunten?';

/// Which hearts-lead restriction applies to King of Hearts and Heart Points.
enum HeartsVariant implements LabeledVariant {
  onlyAfterPlayedHeart,
  graduatedUnlock;

  @override
  String get label => switch (this) {
    .onlyAfterPlayedHeart => 'Na bijgespeelde harten',
    .graduatedUnlock => 'Gefaseerd',
  };

  @override
  String get description => switch (this) {
    .onlyAfterPlayedHeart =>
      'Uitkomen met harten mag pas als er al een harten is (bij)gespeeld.',
    .graduatedUnlock =>
      'Harten is niet toegestaan in de eerste 3 slagen; bijspelen mag in slagen 4 en 5; terugkomen mag vanaf slag 6.',
  };
}
