// =============================================================================
// Game rules — single source of truth for ALL Bonken rule text.
// =============================================================================
//
// All rule text lives here. Do not duplicate any of it in widgets, README,
// or anywhere else: link to it / reference it instead.
//
// The file is intentionally Flutter-free (no Material, no widgets) so the
// content stays portable: any renderer can walk the [Block] tree and
// translate it to its target medium.
// =============================================================================

/// Short tagline rendered just below the rules-screen heading.
const String kRulesTagline =
    'Bonken is een kaartspel voor 4 spelers met een standaard pak van 52 '
    'kaarten (zonder jokers).';

// -----------------------------------------------------------------------------
// Block model
// -----------------------------------------------------------------------------

/// Inline text supports a tiny markdown subset: `**bold**`.
sealed class Block {
  const Block();
}

class Para extends Block {
  const Para(this.text);
  final String text;
}

class BulletList extends Block {
  const BulletList(this.items);
  final List<String> items;
}

class NumberedList extends Block {
  const NumberedList(this.items, {this.startFrom = 1});
  final List<String> items;

  /// Display offset for the first item — allows splitting a list around an
  /// intercalated block while keeping continuous numbering.
  final int startFrom;
}

/// A step in a numbered sequence whose text depends on the active
/// [StarterVariant]. The renderer shows the active variant's text as a regular
/// numbered item and the inactive variant's text as a "Spelregel variant" note.
///
/// Pure Dart data — no Flutter imports.
class StarterVariantBlock extends Block {
  const StarterVariantBlock({
    required this.stepNumber,
    required this.dealerStartsText,
    required this.oppositeChooserStartsText,
  });

  final int stepNumber;
  final String dealerStartsText;
  final String oppositeChooserStartsText;
}

/// An "Extra spelregel" note whose text depends on the active [HeartsVariant].
/// The renderer shows the active variant's text as the main callout and the
/// inactive variant's text as a "Spelregel variant" sub-note.
///
/// Pure Dart data — no Flutter imports.
class HeartsVariantNote extends Block {
  const HeartsVariantNote({
    required this.label,
    required this.onlyAfterPlayedHeartText,
    required this.graduatedUnlockText,
  });

  final String label;
  final String onlyAfterPlayedHeartText;
  final String graduatedUnlockText;
}

class TableBlock extends Block {
  const TableBlock({
    required this.headers,
    required this.rows,
    this.alignRight = const [],
  });
  final List<String> headers;
  final List<List<String>> rows;

  /// 0-based column indices to render right-aligned.
  final List<int> alignRight;
}

/// A labeled callout inside a game section.
class Note extends Block {
  const Note({required this.label, required this.text});

  /// Display label shown in front of the text (e.g. `Voorwaarde`).
  final String label;
  final String text;
}

/// A top-level section in the rules document (`## ...` heading).
class Section {
  const Section({required this.title, required this.blocks});
  final String title;
  final List<Block> blocks;
}

/// Per-game rules section (`### ...` heading inside Positieve / Negatieve).
class GameSection {
  const GameSection({
    required this.gameId,
    required this.title,
    required this.blocks,
  });

  /// Matches `MiniGame.id`.
  final String gameId;
  final String title;
  final List<Block> blocks;
}

// -----------------------------------------------------------------------------
// Reusable text fragments
// -----------------------------------------------------------------------------

/// The "harten alleen na bijgespeelde harten" rule, shared by Harten Heer
/// and Hartenpunten.
const String kHeartsLeadRule =
    'Als je niet kunt bekennen, mag je bijspelen wat je wilt, maar uitkomen en '
    'terugkomen mag alleen met harten als er in een eerdere slag al een keer '
    'harten is (bij)gespeeld of als harten de enige kleur is die je nog op '
    'hand hebt.';

/// The "gefaseerde opening" hearts rule — alternate to [kHeartsLeadRule].
const String kHeartsLeadRuleGraduatedUnlock =
    'In de eerste drie slagen mag je niet met harten uitkomen of terugkomen '
    'en als je niet kan bekennen mag je ook geen harten bijspelen. '
    'Vanaf de vierde slag mag je harten bijspelen als je niet kunt bekennen. '
    'Vanaf de zesde slag mag je met harten terugkomen. '
    'Als harten de enige kleur is die je nog op hand hebt, mag je altijd '
    'harten bijspelen, uitkomen en terugkomen.';

// -----------------------------------------------------------------------------
// Top-of-document sections
// -----------------------------------------------------------------------------

const Section kDoelSection = Section(
  title: 'Doel',
  blocks: [
    Para(
      'Je speelt 12 rondes. Er zijn 13 mogelijke spelvormen: 8 negatieve en '
      '5 positieve. Je speelt altijd alle 8 negatieve spelvormen en 4 van de '
      '5 positieve. Daardoor blijft vanzelf 1 positieve spelvorm over die '
      'niet gespeeld wordt.',
    ),
    Para('Bij negatieve spelvormen probeer je strafpunten te vermijden.'),
    Para('Bij positieve spelvormen probeer je slagen te pakken.'),
    Para('Wie na 12 rondes de meeste punten heeft, wint het spel.'),
    Para(
      'De totale puntentelling van een spel komt altijd op nul uit. De 4 '
      'positieve spelvormen zijn samen goed voor +1040 punten (+260 x 4), en '
      'de 8 negatieve spelvormen zijn samen -1040 punten. De som van de '
      'eindstand van alle vier spelers is altijd nul: wat de ene speler wint '
      'verliest een andere speler.',
    ),
  ],
);

const Section kOpzetSection = Section(
  title: 'Opzet',
  blocks: [
    BulletList([
      '4 spelers',
      '13 kaarten per speler per ronde',
      '12 rondes per spel',
      'één deler per ronde (draait met de klok mee)',
      'één kiezer per ronde (de speler links van de deler)',
      'weinig schudden (voor de scheve verdelingen)',
      'iedereen speelt voor zich (geen paren)',
    ]),
    Para(
      'Over een heel spel is iedereen precies 3 keer deler en 3 keer kiezer.',
    ),
    Para('Voor het kiezen van een spelvorm gelden deze beperkingen:'),
    BulletList([
      'elke speler mag maximaal 2 negatieve spelvormen kiezen',
      'elke speler mag maximaal 1 positieve spelvorm kiezen',
    ]),
    Para('In de praktijk betekent dat:'),
    BulletList([
      'alle 8 negatieve spelvormen worden gespeeld',
      '4 van de 5 positieve spelvormen worden gespeeld',
      '1 positieve spelvorm blijft over en vervalt vanzelf',
      'de kiezer in de laatste ronde heeft bij een negatieve spelvorm een verplichte keus (de rest is al gespeeld)',
    ]),
  ],
);

const Section kSpelvormenSection = Section(
  title: 'Spelvormen',
  blocks: [
    TableBlock(
      headers: ['Spelvorm', 'Soort', 'Waar draait het om?', 'Totaal'],
      alignRight: [3],
      rows: [
        ['Harten Heer', 'Negatief', 'Harten heer vermijden', '-100'],
        ['Heren / Boeren', 'Negatief', 'Heren en boeren vermijden', '-200'],
        ['Vrouwen', 'Negatief', 'Vrouwen vermijden', '-180'],
        ['Bukken', 'Negatief', 'Slagen vermijden', '-130'],
        ['Hartenpunten', 'Negatief', 'Hartenkaarten vermijden', '-130'],
        ['7e / 13e slag', 'Negatief', 'De 7e en 13e slag vermijden', '-100'],
        ['Laatste slag', 'Negatief', 'De laatste slag vermijden', '-100'],
        ['Domino', 'Negatief', 'Niet als laatste eindigen', '-100'],
        ['Klaveren', 'Positief', 'Slagen pakken, klaveren is troef', '+260'],
        ['Ruiten', 'Positief', 'Slagen pakken, ruiten is troef', '+260'],
        ['Harten', 'Positief', 'Slagen pakken, harten is troef', '+260'],
        ['Schoppen', 'Positief', 'Slagen pakken, schoppen is troef', '+260'],
        ['Zonder troef', 'Positief', 'Slagen pakken zonder troef', '+260'],
      ],
    ),
  ],
);

const Section kVerloopSection = Section(
  title: 'Verloop van een ronde',
  blocks: [
    NumberedList([
      'De deler schudt de kaarten (maar niet te veel, maximaal 3 keer heffen).',
      'De deler deelt alle kaarten (13 per speler) met grote stappen (bijvoorbeeld 5-4-4).',
      'Zodra de kaarten zijn gedeeld, mogen alle spelers hun eigen kaarten bekijken.',
      'De speler links van de deler is de kiezer en kiest een spelvorm die nog niet gespeeld is (maximaal 2 negatieve en 1 positieve spelvorm per speler).',
      'Voor het spelen kunnen spelers dubbelen of teruggaan. De speler links van de kiezer gaat eerst, de kiezer als laatst. De kiezer mag niet dubbelen, alleen teruggaan.',
    ]),
    StarterVariantBlock(
      stepNumber: 6,
      dealerStartsText: 'Daarna wordt gespeeld waarbij de deler uitkomt.',
      oppositeChooserStartsText:
          'Daarna wordt gespeeld waarbij de speler tegenover de kiezer uitkomt.',
    ),
    NumberedList([
      'De ronde wordt gescoord.',
      'De volgende speler (met de klok mee) wordt deler.',
    ], startFrom: 7),
  ],
);

const Section kNegatieveIntroSection = Section(
  title: 'Negatieve spelvormen',
  blocks: [
    Para('Bij negatieve spelvormen probeer je strafpunten te vermijden.'),
    Para('Alle negatieve spelvormen speel je zonder troef.'),
    Para(
      'Bij spelvormen die draaien om het vermijden van bepaalde kaarten '
      'eindigt de ronde zodra al die kaarten zijn gespeeld — je speelt '
      'niet verplicht door tot de 13e slag. Bijvoorbeeld bij Vrouwen '
      'eindigt de ronde zodra alle vier vrouwen zijn gespeeld.',
    ),
  ],
);

const Section kPositieveIntroSection = Section(
  title: 'Positieve spelvormen',
  blocks: [
    Para('Bij positieve spelvormen wil je slagen pakken.'),
    Para(
      'Als je niet kunt bekennen, mag je bijspelen wat je wilt. '
      'Je bent niet verplicht te troeven en ook niet verplicht '
      'onder of over te troeven.',
    ),
  ],
);

const Section kDubbelenSection = Section(
  title: 'Dubbelen',
  blocks: [
    Para(
      'Nadat de spelvorm gekozen is en voordat de deler uitkomt, mogen '
      'spelers elkaar dubbelen. De speler links van de kiezer is als eerste '
      'aan de beurt. Daarna gaat dat met de klok mee verder, met de kiezer '
      'als laatste.',
    ),
    Para(
      'Je kiest zelf welke andere spelers je dubbelt. Dat kunnen 1, 2 of 3 '
      'spelers zijn, in elke combinatie die je wilt. Als je precies de 2 '
      'spelers dubbelt die niet de kiezer zijn, noem je dat een Slappe hap '
      'of Ruitenwisser. Als je alle 3 de andere spelers dubbelt, heet dat '
      'een Zaal. Als je niemand wilt dubbelen, dan pas je.',
    ),
    Para(
      'Als iemand jou heeft gedubbeld en je moet zelf nog aan de beurt komen, '
      'dan mag je teruggaan. Ben je al aan de beurt geweest, dan mag je niet '
      'meer teruggaan.',
    ),
    Para(
      'De kiezer mag zelf niemand dubbelen, maar mag wel teruggaan op spelers '
      'die de kiezer hebben gedubbeld.',
    ),
    Para(
      'In Domino geldt de extra voorwaarde dat je pas iemand mag dubbelen of '
      'mag teruggaan op iemand als je minstens één Aas of 2 op hand hebt.',
    ),
    Para(
      'Bij het verrekenen van een dubbel kijk je naar het verschil tussen 2 '
      'spelers in wat de spelvorm telt. Afhankelijk van de spelvorm gaat het '
      'dan bijvoorbeeld om slagen, strafkaarten of strafslagen. Dat verschil '
      'vormt de basis van de verrekening. Bij een dubbel wordt het verschil '
      'één keer verrekend tussen de spelers. Gaat iemand terug, dan wordt het '
      'verschil zelfs twee keer verrekend.',
    ),
    Para(
      'Je vermenigvuldigt het verschil met de waarde per stuk van de spelvorm. '
      'Hebben 2 spelers hetzelfde resultaat, dan is de verrekening 0. Hebben '
      'ze een verschillend resultaat, dan gaan de extra punten naar de speler '
      'met (onderling) het betere resultaat en worden diezelfde punten '
      'afgetrokken van de speler met (onderling) het slechtere resultaat. '
      'Als iemand terug is gegaan doe je dit twee keer.',
    ),
    Para(
      'Deze verrekening gebeurt per dubbel tussen 2 spelers. In het uiterste '
      'geval moeten alle 6 mogelijke dubbels worden verrekend.',
    ),
    Para(
      'Bij het uitrekenen van de score maakt het niet uit wie de dubbel '
      'heeft gedaan. Als speler B speler A dubbelt, maar zelf slechter '
      'scoort in dat spel, dan is de uitkomst hetzelfde als wanneer de '
      'dubbel door speler A was gedaan.',
    ),
    Para(
      '**Voorbeeld 1:** in Vrouwen is elke vrouw -45 punten. Als speler A 3 '
      'vrouwen wint en speler B 1 vrouw wint, zit er 2 vrouwen verschil '
      'tussen hen. Als speler A is gedubbeld door speler B, worden die 2 '
      'strafkaarten extra verrekend. A krijgt dan 2 x -45 = -90 punten, en B '
      'krijgt 2 x +45 = +90 punten. Is A terug gegaan, dan verreken je nog '
      'een keer het verschil en krijgt A -180 punten en B +180 punten. '
      'Dit is bovenop de gewone score van het spel en andere dubbels. '
      'Zonder andere dubbels zou B in totaal +135 punten krijgen deze ronde '
      '(1 x -45 = -45 voor de vrouw en +180 voor de dubbel met teruggaan).',
    ),
    Para(
      '**Voorbeeld 2:** in Harten is elke slag +20. Als speler A 2 slagen '
      'wint en speler B 7 slagen wint, zit er 5 slagen verschil tussen hen. '
      'Als speler A is gedubbeld door speler B, worden die 5 slagen extra '
      'verrekend. A krijgt dan 5 x -20 = -100 punten, en B krijgt 5 x +20 = '
      '+100 punten. Is A terug gegaan, dan verreken je nog een keer het '
      'verschil en krijgt A -200 punten en B +200 punten. '
      'Dit is bovenop de gewone score van het spel en andere dubbels. '
      'Zonder andere dubbels zou A in totaal -160 punten krijgen deze ronde '
      '(2 x +20 = +40 voor de slagen en -200 voor de dubbel met teruggaan).',
    ),
  ],
);

// -----------------------------------------------------------------------------
// Per-game sections
// -----------------------------------------------------------------------------

GameSection _trickGame({
  required String gameId,
  required String displayName,
  required String suitDescription,
  required int example,
}) {
  final scorePart = '$example x +20 = +${example * 20}';
  return GameSection(
    gameId: gameId,
    title: '$displayName (totaal +260)',
    blocks: [
      const Para('In deze spelvorm wil je slagen pakken.'),
      Para(suitDescription),
      const Para('**Elke gewonnen slag is +20.**'),
      Para(
        '**Voorbeeld:** als jij $example ${example == 1 ? 'slag' : 'slagen'} wint, krijg je $scorePart.',
      ),
      const Para('13 slagen x +20 = +260 totaal.'),
    ],
  );
}

const GameSection _zonderTroefSection = GameSection(
  gameId: 'noTrump',
  title: 'Zonder troef (totaal +260)',
  blocks: [
    Para('In deze spelvorm wil je slagen pakken.'),
    Para('Je speelt zonder troef.'),
    Para('**Elke gewonnen slag is +20.**'),
    Para(
      '**Voorbeeld:** als de slagen worden verdeeld als 6, 4, 2 en 1, dan '
      'zijn de scores +120, +80, +40 en +20.',
    ),
    Para('13 slagen x +20 = +260 totaal.'),
  ],
);

const GameSection _kingOfHeartsSection = GameSection(
  gameId: 'kingOfHearts',
  title: 'Harten Heer (totaal -100)',
  blocks: [
    Para('**Wie de slag wint waarin de harten heer valt, krijgt -100.**'),
    HeartsVariantNote(
      label: 'Extra spelregel',
      onlyAfterPlayedHeartText: kHeartsLeadRule,
      graduatedUnlockText: kHeartsLeadRuleGraduatedUnlock,
    ),
  ],
);

const GameSection _kingsAndJacksSection = GameSection(
  gameId: 'kingsAndJacks',
  title: 'Heren / Boeren (totaal -200)',
  blocks: [
    Para('**Elke heer of boer in jouw gewonnen slagen is -25.**'),
    Para(
      'Heren en boeren die zijn bijgespeeld door iemand die niet kon '
      'bekennen tellen ook mee.',
    ),
    Para(
      '**Voorbeeld:** als jij 3 heren of boeren in je gewonnen slagen '
      'hebt, krijg je 3 x -25 = -75.',
    ),
    Para('8 kaarten x -25 = -200 totaal.'),
  ],
);

const GameSection _queensSection = GameSection(
  gameId: 'queens',
  title: 'Vrouwen (totaal -180)',
  blocks: [
    Para('**Elke vrouw in jouw gewonnen slagen is -45.**'),
    Para(
      'Vrouwen die zijn bijgespeeld door iemand die niet kon '
      'bekennen tellen ook mee.',
    ),
    Para(
      '**Voorbeeld:** als jij 2 vrouwen in je gewonnen slagen '
      'hebt, krijg je 2 x -45 = -90.',
    ),
    Para('4 kaarten x -45 = -180 totaal.'),
  ],
);

const GameSection _duckSection = GameSection(
  gameId: 'duck',
  title: 'Bukken (totaal -130)',
  blocks: [
    Para('**Elke gewonnen slag is -10.**'),
    Para('Hoe meer slagen je wint, hoe meer strafpunten je krijgt.'),
    Para('**Voorbeeld:** als jij 4 slagen wint, krijg je 4 x -10 = -40.'),
    Para('13 slagen x -10 = -130 totaal.'),
  ],
);

const GameSection _heartPointsSection = GameSection(
  gameId: 'heartPoints',
  title: 'Hartenpunten (totaal -130)',
  blocks: [
    Para('**Elke hartenkaart in jouw gewonnen slagen is -10.**'),
    Para(
      'Hartenkaarten die zijn bijgespeeld door iemand die niet kon '
      'bekennen tellen ook mee.',
    ),
    HeartsVariantNote(
      label: 'Extra spelregel',
      onlyAfterPlayedHeartText: kHeartsLeadRule,
      graduatedUnlockText: kHeartsLeadRuleGraduatedUnlock,
    ),
    Para(
      '**Voorbeeld:** als jij 5 hartenkaarten in je gewonnen slagen '
      'hebt, krijg je 5 x -10 = -50.',
    ),
    Para('13 hartenkaarten x -10 = -130 totaal.'),
  ],
);

const GameSection _seventhAndThirteenthSection = GameSection(
  gameId: 'seventhAndThirteenth',
  title: '7e / 13e slag (totaal -100)',
  blocks: [
    Para(
      '**De winnaar van de 7e slag krijgt -50. '
      'De winnaar van de 13e slag krijgt ook -50.**',
    ),
    Para(
      'Dat kan dezelfde speler zijn (dan krijgt die -100), '
      'of twee verschillende spelers (elk -50).',
    ),
  ],
);

const GameSection _finalTrickSection = GameSection(
  gameId: 'finalTrick',
  title: 'Laatste slag (totaal -100)',
  blocks: [
    Para(
      '**De winnaar van de 13e slag (de allerlaatste slag van de ronde) krijgt -100.**',
    ),
  ],
);

const GameSection _dominoesSection = GameSection(
  gameId: 'dominoes',
  title: 'Domino (totaal -100)',
  blocks: [
    Para('Dit is de enige spelvorm waar je niet met slagen speelt.'),
    Para('Je bouwt met de kaarten op tafel vier rijen, één per kleur.'),
    Note(
      label: 'Voorwaarde om te kiezen',
      text:
          'Je mag Domino alleen kiezen als je minstens één Aas of 2 op hand '
          'hebt. Deze voorwaarde vervalt als het de laatste ronde is en '
          'Domino de enige overgebleven spelvorm is.',
    ),
    Note(
      label: 'Voorwaarde bij dubbelen',
      text:
          'Je mag alleen dubbelen of teruggaan als je minstens '
          'één Aas of 2 op hand hebt.',
    ),
    Para('Het verloop is als volgt:'),
    NumberedList([
      'De deler begint.',
      'Iedere kleur begint met de 8. Een kleur komt pas op tafel zodra iemand de 8 van die kleur speelt.',
      'Ligt een kleur al op tafel, dan mag je in die kleur alleen 1 hoger of 1 lager aanleggen.',
      'De eerste Aas mag óf omhoog aan de Heer worden aangelegd, óf omlaag aan de 2 worden aangelegd. De andere drie azen moeten daarna in dezelfde richting als de eerste Aas aangelegd worden.',
      'Kun je aanleggen bij een kleur die al op tafel ligt, dan moet je eerst aanleggen.',
      'Kun je niet aanleggen, maar heb je wel een 8 op hand, dan moet je een 8 spelen. Heb je meerdere achten, dan mag je kiezen welke je speelt.',
      'Passen mag alleen als je niet kunt aanleggen en ook geen 8 op hand hebt.',
      'Wie als laatste uit is krijgt -100.',
    ]),
  ],
);

/// All per-game rule sections, matching the display order of [allGames]
/// (negatives first, then positives).
final List<GameSection> kGameSections = [
  // Negative games
  _kingOfHeartsSection,
  _kingsAndJacksSection,
  _queensSection,
  _duckSection,
  _heartPointsSection,
  _seventhAndThirteenthSection,
  _finalTrickSection,
  _dominoesSection,
  // Positive games
  _trickGame(
    gameId: 'clubs',
    displayName: 'Klaveren',
    suitDescription: 'Klaveren is troef.',
    example: 6,
  ),
  _trickGame(
    gameId: 'diamonds',
    displayName: 'Ruiten',
    suitDescription: 'Ruiten is troef.',
    example: 4,
  ),
  _trickGame(
    gameId: 'hearts',
    displayName: 'Harten',
    suitDescription: 'Harten is troef.',
    example: 2,
  ),
  _trickGame(
    gameId: 'spades',
    displayName: 'Schoppen',
    suitDescription: 'Schoppen is troef.',
    example: 1,
  ),
  _zonderTroefSection,
];

/// Lookup helper: returns the [GameSection] for a given `MiniGame.id`,
/// or `null` if no rules are defined for it.
GameSection? gameSectionFor(String gameId) {
  for (final s in kGameSections) {
    if (s.gameId == gameId) return s;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Document order — used by the in-app rules screen.
// -----------------------------------------------------------------------------

/// Top-level non-game sections, in document order, that come BEFORE the
/// per-game listings.
const List<Section> kSectionsBeforeGames = [
  kDoelSection,
  kOpzetSection,
  kSpelvormenSection,
  kVerloopSection,
];

/// Top-level non-game sections that come AFTER the per-game listings.
const List<Section> kSectionsAfterGames = [kDubbelenSection];
