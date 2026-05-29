const String kHeartsVariantSectionTitle = 'Extra spelregel harten';
const String kHeartsVariantSectionSubtitle =
    'Welke extra spelregel geldt voor Harten Heer en Hartenpunten?';

/// Which hearts-lead restriction applies to King of Hearts and Heart Points.
enum HeartsVariant {
  onlyAfterPlayedHeart,
  graduatedUnlock;

  String get label => switch (this) {
    HeartsVariant.onlyAfterPlayedHeart => 'Na bijgespeelde harten',
    HeartsVariant.graduatedUnlock => 'Gefaseerde opening',
  };

  String get description => switch (this) {
    HeartsVariant.onlyAfterPlayedHeart =>
      'Uitkomen met harten mag pas als er al een harten is (bij)gespeeld.',
    HeartsVariant.graduatedUnlock =>
      'Harten is niet toegestaan in de eerste 3 slagen; bijspelen mag in slagen 4 en 5; terugkomen mag vanaf slag 6.',
  };
}
