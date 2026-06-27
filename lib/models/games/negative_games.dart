import 'package:material_symbols_icons/symbols.dart';

import '../mini_game.dart';

// =============================================================================
// Negative game 1 — Harten Heer (King of Hearts)
// =============================================================================
// The player who wins the trick containing the King of Hearts loses -100.
// Only one player can win it. Single-recipient pick; total -100.

class KingOfHearts extends RecipientMiniGame {
  const KingOfHearts()
    : super(
        id: 'kingOfHearts',
        name: 'Harten Heer',
        symbol: const TextSymbol('HH'),
        category: GameCategory.negative,
        pointsPerUnit: -100,
        totalPoints: -100,
        prompts: const ['Wie won de Harten Heer slag?'],
      );
}

// =============================================================================
// Negative game 2 — Heren / Boeren (Kings / Jacks)
// =============================================================================
// Each King or Jack (8 cards total) costs -25 to the player who won that trick.
// Per-player counts summing to 8; total 8 × -25 = -200.

class KingsAndJacks extends CountsMiniGame {
  const KingsAndJacks()
    : super(
        id: 'kingsAndJacks',
        name: 'Heren / Boeren',
        symbol: const TextSymbol('H/B'),
        category: GameCategory.negative,
        pointsPerUnit: -25,
        totalPoints: -200,
        total: 8,
        unitLabel: 'heren/boeren',
      );
}

// =============================================================================
// Negative game 3 — Vrouwen (Queens)
// =============================================================================
// Each Queen (4 cards) costs -45 to the player who won that trick.
// Per-player counts summing to 4; total 4 × -45 = -180.

class Queens extends CountsMiniGame {
  const Queens()
    : super(
        id: 'queens',
        name: 'Vrouwen',
        symbol: const TextSymbol('V'),
        category: GameCategory.negative,
        pointsPerUnit: -45,
        totalPoints: -180,
        total: 4,
        unitLabel: 'vrouwen',
      );
}

// =============================================================================
// Negative game 4 — Bukken (Duck)
// =============================================================================
// Every trick won costs -10. Per-player counts summing to 13 → -130.

class Duck extends CountsMiniGame {
  const Duck()
    : super(
        id: 'duck',
        name: 'Bukken',
        symbol: const IconSymbol(Symbols.keyboard_double_arrow_down),
        category: GameCategory.negative,
        pointsPerUnit: -10,
        totalPoints: -130,
        total: 13,
        unitLabel: 'slagen',
      );
}

// =============================================================================
// Negative game 5 — Hartenpunten (Heart points)
// =============================================================================
// Every Heart card won in a trick costs -10. Per-player counts summing to
// 13 → -130.

class HeartPoints extends CountsMiniGame {
  const HeartPoints()
    : super(
        id: 'heartPoints',
        name: 'Hartenpunten',
        symbol: const IconSymbol(Symbols.heart_broken),
        category: GameCategory.negative,
        pointsPerUnit: -10,
        totalPoints: -130,
        total: 13,
        unitLabel: 'harten',
      );
}

// =============================================================================
// Negative game 6 — 7e / 13e (7th / 13th trick)
// =============================================================================
// Winning the 7th trick costs -50; winning the 13th trick costs -50. Both can
// be won by the same player (-100) or different players. Two independent
// recipient slots (7th, then 13th); total always -100.

class SeventhAndThirteenth extends RecipientMiniGame {
  const SeventhAndThirteenth()
    : super(
        id: 'seventhAndThirteenth',
        name: '7e / 13e',
        symbol: const TextSymbol('7/13'),
        category: GameCategory.negative,
        pointsPerUnit: -50,
        totalPoints: -100,
        prompts: const ['Wie won de 7e slag?', 'Wie won de 13e slag?'],
      );
}

// =============================================================================
// Negative game 7 — Laatste slag (Final trick)
// =============================================================================
// Winning the 13th (final) trick costs -100. Single-recipient pick; total -100.

class FinalTrick extends RecipientMiniGame {
  const FinalTrick()
    : super(
        id: 'finalTrick',
        name: 'Laatste slag',
        symbol: const TextSymbol('13'),
        category: GameCategory.negative,
        pointsPerUnit: -100,
        totalPoints: -100,
        prompts: const ['Wie won de laatste slag?'],
      );
}

// =============================================================================
// Negative game 8 — Domino
// =============================================================================
// The player forced to play the last card of the game loses -100. Different
// gameplay (not card-trick based) but the scoring model is identical to
// FinalTrick: one player gets the penalty. Single-recipient pick; total -100.

class Dominoes extends RecipientMiniGame {
  const Dominoes()
    : super(
        id: 'dominoes',
        name: 'Domino',
        symbol: const TextSymbol('D'),
        category: GameCategory.negative,
        pointsPerUnit: -100,
        totalPoints: -100,
        prompts: const ['Wie speelde de laatste kaart?'],
      );
}
