import '../input_descriptor.dart';
import '../mini_game.dart';

/// Shared base for all 5 positive trick-taking mini-games.
///
/// Input key: 'tricks' — List of length 4 (tricks per player).
/// Total score: 13 tricks × +20 = +260.
abstract class PositiveGame extends MiniGame {
  const PositiveGame({required super.id, required super.name})
    : super(
        category: GameCategory.positive,
        pointsPerUnit: 20,
        totalPoints: 260,
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

/// Klaveren (Clubs) – Clubs is trump.
class Clubs extends PositiveGame {
  const Clubs() : super(id: 'clubs', name: 'Klaveren');
}

/// Ruiten (Diamonds) – Diamonds is trump.
class Diamonds extends PositiveGame {
  const Diamonds() : super(id: 'diamonds', name: 'Ruiten');
}

/// Harten (Hearts) – Hearts is trump.
class Hearts extends PositiveGame {
  const Hearts() : super(id: 'hearts', name: 'Harten');
}

/// Schoppen (Spades) – Spades is trump.
class Spades extends PositiveGame {
  const Spades() : super(id: 'spades', name: 'Schoppen');
}

/// Zonder troef (No Trump) – No trump suit; highest card of led suit wins.
class NoTrump extends PositiveGame {
  const NoTrump() : super(id: 'noTrump', name: 'Zonder troef');
}
