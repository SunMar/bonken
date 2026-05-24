import '../mini_game.dart';

/// Shared base for all 5 positive trick-taking mini-games: 13 tricks summing to
/// +260 (13 × +20). All counts behaviour (input key, descriptor, scoring,
/// storage round-trip) comes from [CountsMiniGame].
abstract class PositiveGame extends CountsMiniGame {
  const PositiveGame({
    required super.id,
    required super.name,
    required super.symbol,
  }) : super(
         category: GameCategory.positive,
         pointsPerUnit: 20,
         totalPoints: 260,
         total: 13,
         unitLabel: 'slagen',
       );
}

/// Klaveren (Clubs) – Clubs is trump.
class Clubs extends PositiveGame {
  const Clubs()
    : super(id: 'clubs', name: 'Klaveren', symbol: const SuitSymbol('♣'));
}

/// Ruiten (Diamonds) – Diamonds is trump.
class Diamonds extends PositiveGame {
  const Diamonds()
    : super(id: 'diamonds', name: 'Ruiten', symbol: const SuitSymbol('♦'));
}

/// Harten (Hearts) – Hearts is trump.
class Hearts extends PositiveGame {
  const Hearts()
    : super(id: 'hearts', name: 'Harten', symbol: const SuitSymbol('♥'));
}

/// Schoppen (Spades) – Spades is trump.
class Spades extends PositiveGame {
  const Spades()
    : super(id: 'spades', name: 'Schoppen', symbol: const SuitSymbol('♠'));
}

/// Zonder troef (No Trump) – No trump suit; highest card of led suit wins.
class NoTrump extends PositiveGame {
  const NoTrump()
    : super(
        id: 'noTrump',
        name: 'Zonder troef',
        symbol: const TextSymbol('SA'),
      );
}
