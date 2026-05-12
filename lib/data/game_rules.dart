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
  const NumberedList(this.items);
  final List<String> items;
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
    'Als je niet kan bekennen mag je bijspelen wat je wil, maar uitkomen en '
    'terugkomen mag alleen met harten als er in een eerdere slag al een keer '
    'een harten is (bij)gespeeld. Is er nog geen harten (bij)gespeeld, maar '
    'heb je alleen nog harten op hand, dan mag je wel harten spelen.';

// -----------------------------------------------------------------------------
// Top-of-document sections
// -----------------------------------------------------------------------------

const Section kDoelSection = Section(
  title: 'Doel van het spel',
  blocks: [
    Para(
      'Je speelt een pot van 12 rondes. Er zijn 13 mogelijke spellen: 5 '
      'positieve en 8 negatieve. In een pot speel je altijd alle 8 negatieve '
      'spellen en 4 van de 5 positieve. Daardoor blijft vanzelf 1 positief '
      'spel over dat niet gespeeld wordt.',
    ),
    Para(
      'Bonken draait in elke ronde om dezelfde vraag: waar wil je in dit '
      'spel juist wel of juist niet op spelen?',
    ),
    Para('Bij positieve spellen probeer je slagen te pakken.'),
    Para('Bij negatieve spellen probeer je strafpunten te vermijden.'),
    Para('Wie na 12 rondes de meeste punten heeft, wint de pot.'),
    Para(
      'De totale puntentelling van een pot komt altijd op nul uit. De 4 '
      'positieve spellen in een pot zijn samen goed voor +1040 punten '
      '(+260 x 4), en de 8 negatieve spellen samen voor -1040 punten. De som '
      'van de eindstand van alle vier spelers is altijd nul: wat de ene '
      'speler wint, verliest een andere speler.',
    ),
  ],
);

const Section kOpzetSection = Section(
  title: 'Opzet van een pot',
  blocks: [
    BulletList([
      '4 spelers',
      '13 kaarten per speler per ronde',
      '12 rondes per pot',
      'één deler per ronde (draait met de klok mee)',
      'één kiezer per ronde (de speler links van de deler)',
    ]),
    Para(
      'Over een hele pot is iedereen precies 3 keer deler en 3 keer kiezer.',
    ),
    Para(
      'Tijdens een pot geldt ook nog deze beperking voor het kiezen van spellen:',
    ),
    BulletList([
      'elke speler mag maximaal 2 negatieve spellen kiezen',
      'elke speler mag maximaal 1 positief spel kiezen',
    ]),
    Para('In de praktijk betekent dat:'),
    BulletList([
      'alle 8 negatieve spellen worden gespeeld',
      '4 van de 5 positieve spellen worden gespeeld',
      '1 positief spel blijft over en vervalt vanzelf',
    ]),
  ],
);

const Section kSpeloverzichtSection = Section(
  title: 'Speloverzicht',
  blocks: [
    TableBlock(
      headers: ['Spel', 'Soort', 'Waar draait het om?', 'Totaal'],
      alignRight: [3],
      rows: [
        ['Klaveren', 'Positief', 'Slagen pakken, klaveren is troef', '+260'],
        ['Ruiten', 'Positief', 'Slagen pakken, ruiten is troef', '+260'],
        ['Harten', 'Positief', 'Slagen pakken, harten is troef', '+260'],
        ['Schoppen', 'Positief', 'Slagen pakken, schoppen is troef', '+260'],
        ['Zonder troef', 'Positief', 'Slagen pakken zonder troef', '+260'],
        ['Harten Heer', 'Negatief', 'Harten heer vermijden', '-100'],
        ['Heren / Boeren', 'Negatief', 'Heren en boeren vermijden', '-200'],
        ['Vrouwen', 'Negatief', 'Vrouwen vermijden', '-180'],
        ['Bukken', 'Negatief', 'Slagen vermijden', '-130'],
        ['Hartenpunten', 'Negatief', 'Hartenkaarten vermijden', '-130'],
        ['7e / 13e slag', 'Negatief', 'De 7e en 13e slag vermijden', '-100'],
        ['Laatste slag', 'Negatief', 'De laatste slag vermijden', '-100'],
        ['Domino', 'Negatief', 'Niet als laatste eindigen', '-100'],
      ],
    ),
  ],
);

const Section kVerloopSection = Section(
  title: 'Verloop van een ronde',
  blocks: [
    NumberedList([
      'De deler deelt alle kaarten (13 per speler).',
      'De speler links van de deler is de kiezer en kiest een spel dat nog niet gespeeld is.',
      'Voor het spelen kunnen spelers dubbelen of teruggaan.',
      'Daarna wordt gespeeld (de deler komt uit).',
      'De ronde wordt gescoord.',
      'De deler schuift één plek door met de klok mee.',
    ]),
    Para(
      'Bij 12 van de 13 spellen speel je een gewoon slagenspel. Alleen Domino werkt anders.',
    ),
  ],
);

const Section kPositieveIntroSection = Section(
  title: 'Positieve spellen',
  blocks: [Para('Bij een positief spel wil je slagen pakken.')],
);

const Section kNegatieveIntroSection = Section(
  title: 'Negatieve spellen',
  blocks: [
    Para('Bij negatieve spellen probeer je strafpunten te vermijden.'),
    Para('Alle negatieve spellen speel je zonder troef.'),
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
      'een Zaal.',
    ),
    Para(
      'Als iemand jou heeft gedubbeld en je moet zelf nog aan de beurt komen, '
      'dan mag je teruggaan. Ben je al aan de beurt geweest, dan mag je niet '
      'meer teruggaan. Wie bij de eigen beurt past, kan later in die ronde '
      'ook niet meer teruggaan.',
    ),
    Para(
      'De kiezer mag zelf niemand dubbelen, maar mag wel teruggaan als '
      'iemand de kiezer heeft gedubbeld.',
    ),
    Para(
      'In Domino geldt de extra voorwaarde dat je pas iemand mag dubbelen of '
      'mag teruggaan op iemand als je minstens één Aas of 2 op hand hebt.',
    ),
    Para(
      'Bij het verrekenen van een dubbel kijk je eerst naar het verschil '
      'tussen 2 spelers in wat de spelvorm telt. Afhankelijk van het spel '
      'gaat het dan bijvoorbeeld om slagen, strafkaarten of strafslagen. Dat '
      'verschil vormt de basis van de verrekening. Bij een dubbel wordt dat '
      'verschil 1 keer extra meegerekend. Gaat iemand terug, dan wordt het '
      'verschil zelfs verdubbeld. Daarna vermenigvuldig je dat verschil met '
      'de waarde per stuk van de spelvorm. Hebben 2 spelers hetzelfde '
      'resultaat, dan is de verrekening 0. Hebben ze een verschillend '
      'resultaat, dan gaan de extra punten naar de speler met (onderling) '
      'het betere resultaat en worden diezelfde punten afgetrokken van de '
      'speler met (onderling) het slechtere resultaat.',
    ),
    Para(
      'Deze verrekening gebeurt per dubbel tussen 2 spelers. In een ronde '
      'kunnen meerdere dubbels naast elkaar actief zijn. In het uiterste '
      'geval moeten zelfs alle 6 mogelijke dubbels apart worden verrekend.',
    ),
    Para(
      'Bij het uitrekenen van de score maakt het niet uit wie de dubbel '
      'heeft gedaan. Als speler B speler A dubbelt, maar zelf slechter '
      'scoort in dat spel, dan is de uitkomst hetzelfde als wanneer de '
      'dubbel door speler A was gedaan.',
    ),
    Para(
      '**Voorbeeld 1:** in Vrouwen is elke vrouw -45 punten. Als speler A 1 '
      'vrouw wint en speler B 3 vrouwen wint, zit er 2 vrouwen verschil '
      'tussen hen. Als speler A is gedubbeld door speler B, worden die 2 '
      'strafkaarten nog 1 keer extra verrekend. A krijgt daardoor 2 x -45 = '
      '-90 punten, en B krijgt 2 x +45 = +90 punten. Gaat A terug, dan wordt '
      'het verschil verdubbeld en krijgt A -180 punten en B +180 punten.',
    ),
    Para(
      '**Voorbeeld 2:** in Harten is elke slag +20. Als speler A 2 slagen '
      'wint en speler B 7 slagen wint, zit er 5 slagen verschil tussen hen. '
      'Als speler A is gedubbeld door speler B, worden die 5 slagen nog 1 '
      'keer extra verrekend. A krijgt daardoor 5 x -20 = -100 punten, en B '
      'krijgt 5 x +20 = +100 punten. Gaat A terug, dan wordt het verschil '
      'verdubbeld en krijgt A -200 punten en B +200 punten.',
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
      const Para('In dit spel wil je slagen pakken.'),
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
    Para('In dit spel wil je slagen pakken.'),
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
    Note(label: 'Extra spelregel', text: kHeartsLeadRule),
  ],
);

const GameSection _kingsAndJacksSection = GameSection(
  gameId: 'kingsAndJacks',
  title: 'Heren / Boeren (totaal -200)',
  blocks: [
    Para('**Elke heer of boer in jouw gewonnen slagen is -25.**'),
    Para(
      'Heren en boeren die zijn bijgespeeld door iemand die niet kon bekennen tellen ook mee.',
    ),
    Para(
      '**Voorbeeld:** als jij 3 heren of boeren in je gewonnen slagen hebt, krijg je 3 x -25 = -75.',
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
      'Vrouwen die zijn bijgespeeld door iemand die niet kon bekennen tellen ook mee.',
    ),
    Para(
      '**Voorbeeld:** als jij 2 vrouwen in je gewonnen slagen hebt, krijg je 2 x -45 = -90.',
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
      'Hartenkaarten die zijn bijgespeeld door iemand die niet kon bekennen tellen ook mee.',
    ),
    Note(label: 'Extra spelregel', text: kHeartsLeadRule),
    Para(
      '**Voorbeeld:** als jij 5 hartenkaarten in je gewonnen slagen hebt, krijg je 5 x -10 = -50.',
    ),
    Para('13 hartenkaarten x -10 = -130 totaal.'),
  ],
);

const GameSection _seventhAndThirteenthSection = GameSection(
  gameId: 'seventhAndThirteenth',
  title: '7e / 13e slag (totaal -100)',
  blocks: [
    Para(
      '**De winnaar van de 7e slag krijgt -50. De winnaar van de 13e slag krijgt ook -50.**',
    ),
    Para(
      'Dat kan dezelfde speler zijn (dan krijgt die -100), of twee verschillende spelers (elk -50).',
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
    Para('In dit spel speel je geen slagen.'),
    Para('Je bouwt met de kaarten op tafel vier rijen, één per kleur.'),
    Note(
      label: 'Voorwaarde',
      text:
          'Je mag Domino alleen kiezen als je minstens één Aas of 2 op hand '
          'hebt (of in de laatste ronde als Domino het enige overgebleven '
          'spel is).',
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

/// All per-game sections, in the canonical play order matching `allGames`.
final List<GameSection> kGameSections = [
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
  // Negative games
  _kingOfHeartsSection,
  _kingsAndJacksSection,
  _queensSection,
  _duckSection,
  _heartPointsSection,
  _seventhAndThirteenthSection,
  _finalTrickSection,
  _dominoesSection,
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
  kSpeloverzichtSection,
  kVerloopSection,
];

/// Top-level non-game sections that come AFTER the per-game listings.
const List<Section> kSectionsAfterGames = [kDubbelenSection];
