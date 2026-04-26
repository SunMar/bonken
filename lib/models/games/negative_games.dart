import '../input_descriptor.dart';
import '../mini_game.dart';

// =============================================================================
// Negative game 1 — Harten Heer (King of Hearts)
// =============================================================================
// The player who wins the trick containing the King of Hearts loses -100.
// Only one player can win it, so rawCount is 0 or 1 (boolean as int).
// Total: -100.
//
// Input key: 'winner' → int (player index 0–3 who won the King of Hearts trick)

class KingOfHearts extends MiniGame {
  const KingOfHearts()
    : super(
        id: 'kingOfHearts',
        name: 'Harten Heer',
        category: GameCategory.negative,
        pointsPerUnit: -100,
        totalPoints: -100,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final winner = input['winner'] as int;
    return [for (int i = 0; i < playerCount; i++) i == winner ? 1 : 0];
  }

  @override
  InputDescriptor get inputDescriptor => const SinglePlayerInputDescriptor(
    inputKey: 'winner',
    prompt: 'Wie won de Harten Heer slag?',
  );
}

// =============================================================================
// Negative game 2 — Heren / Boeren (Kings / Jacks)
// =============================================================================
// Each King or Jack (8 cards total) costs -25 to the player who won that trick.
// Total: 8 × -25 = -200.
//
// Input key: 'cards' → List<int> of length 4 (number of kings+jacks won per player)

class KingsAndJacks extends MiniGame {
  const KingsAndJacks()
    : super(
        id: 'kingsAndJacks',
        name: 'Heren / Boeren',
        category: GameCategory.negative,
        pointsPerUnit: -25,
        totalPoints: -200,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final cards = (input['cards'] as List).cast<int>();
    assert(cards.length == 4);
    return cards;
  }

  @override
  InputDescriptor get inputDescriptor => const CountsInputDescriptor(
    inputKey: 'cards',
    total: 8,
    unitLabel: 'heren/boeren',
  );
}

// =============================================================================
// Negative game 3 — Vrouwen (Queens)
// =============================================================================
// Each Queen (4 cards) costs -45 to the player who won that trick.
// Total: 4 × -45 = -180.
//
// Input key: 'cards' → List<int> of length 4 (number of queens won per player)

class Queens extends MiniGame {
  const Queens()
    : super(
        id: 'queens',
        name: 'Vrouwen',
        category: GameCategory.negative,
        pointsPerUnit: -45,
        totalPoints: -180,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final cards = (input['cards'] as List).cast<int>();
    assert(cards.length == 4);
    return cards;
  }

  @override
  InputDescriptor get inputDescriptor => const CountsInputDescriptor(
    inputKey: 'cards',
    total: 4,
    unitLabel: 'vrouwen',
  );
}

// =============================================================================
// Negative game 4 — Bukken (Duck)
// =============================================================================
// Every trick won costs -10.  13 tricks total → -130.
//
// Input key: 'tricks' → List<int> of length 4 (tricks won per player)

class Duck extends MiniGame {
  const Duck()
    : super(
        id: 'duck',
        name: 'Bukken',
        category: GameCategory.negative,
        pointsPerUnit: -10,
        totalPoints: -130,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final tricks = (input['tricks'] as List).cast<int>();
    assert(tricks.length == 4);
    return tricks;
  }

  @override
  InputDescriptor get inputDescriptor => const CountsInputDescriptor(
    inputKey: 'tricks',
    total: 13,
    unitLabel: 'slagen',
  );
}

// =============================================================================
// Negative game 5 — Harten punten (Heart points)
// =============================================================================
// Every Heart card won in a trick costs -10.  13 hearts → -130.
//
// Input key: 'cards' → List<int> of length 4 (heart cards won per player)

class HeartPoints extends MiniGame {
  const HeartPoints()
    : super(
        id: 'heartPoints',
        name: 'Harten punten',
        category: GameCategory.negative,
        pointsPerUnit: -10,
        totalPoints: -130,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final cards = (input['cards'] as List).cast<int>();
    assert(cards.length == 4);
    return cards;
  }

  @override
  InputDescriptor get inputDescriptor => const CountsInputDescriptor(
    inputKey: 'cards',
    total: 13,
    unitLabel: 'harten',
  );
}

// =============================================================================
// Negative game 6 — 7e / 13e (7th / 13th trick)
// =============================================================================
// Winning the 7th trick costs -50; winning the 13th trick costs -50.
// Both can be won by the same player (costing them -100 total) or different
// players.  Total always: -100.
//
// We model it as a count of "penalty tricks" per player (0, 1, or 2),
// each worth -50.
//
// Input keys:
//   'trick7winner'  → int (player index)
//   'trick13winner' → int (player index)

class SeventhAndThirteenth extends MiniGame {
  const SeventhAndThirteenth()
    : super(
        id: 'seventhAndThirteenth',
        name: '7e / 13e',
        category: GameCategory.negative,
        pointsPerUnit: -50,
        totalPoints: -100,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final w7 = input['trick7winner'] as int;
    final w13 = input['trick13winner'] as int;
    final counts = [0, 0, 0, 0];
    counts[w7]++;
    counts[w13]++;
    return counts;
  }

  @override
  InputDescriptor get inputDescriptor => const DualPlayerInputDescriptor(
    inputKey1: 'trick7winner',
    prompt1: 'Wie won de 7e slag?',
    inputKey2: 'trick13winner',
    prompt2: 'Wie won de 13e slag?',
  );
}

// =============================================================================
// Negative game 7 — Laatste slag (Final trick)
// =============================================================================
// Winning the 13th (final) trick costs -100.
// Only one player can win it.  Total: -100.
//
// Input key: 'winner' → int (player index)

class FinalTrick extends MiniGame {
  const FinalTrick()
    : super(
        id: 'finalTrick',
        name: 'Laatste slag',
        category: GameCategory.negative,
        pointsPerUnit: -100,
        totalPoints: -100,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final winner = input['winner'] as int;
    return [for (int i = 0; i < playerCount; i++) i == winner ? 1 : 0];
  }

  @override
  InputDescriptor get inputDescriptor => const SinglePlayerInputDescriptor(
    inputKey: 'winner',
    prompt: 'Wie won de laatste slag?',
  );
}

// =============================================================================
// Negative game 8 — Dominos
// =============================================================================
// The player forced to play the last card of the game loses -100.
// Only one player receives the penalty.  Total: -100.
//
// Dominos has different gameplay (not card-trick based) but the scoring
// model is identical to FinalTrick: one player gets the penalty.
//
// Input key: 'loser' → int (player index who played the last card)

class Dominoes extends MiniGame {
  const Dominoes()
    : super(
        id: 'dominoes',
        name: 'Domino',
        category: GameCategory.negative,
        pointsPerUnit: -100,
        totalPoints: -100,
      );

  @override
  List<int> rawCounts(Map<String, dynamic> input) {
    final loser = input['loser'] as int;
    return [for (int i = 0; i < playerCount; i++) i == loser ? 1 : 0];
  }

  @override
  InputDescriptor get inputDescriptor => const SinglePlayerInputDescriptor(
    inputKey: 'loser',
    prompt: 'Wie speelde de laatste kaart?',
  );
}
