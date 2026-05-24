import 'double_matrix.dart';
import 'mini_game.dart';

/// Stores everything about a completed round so it can be shown in history
/// and restored for editing if needed.
class RoundRecord {
  const RoundRecord({
    required this.roundNumber,
    required this.game,
    required this.chooserId,
    required this.scoresByPlayer,
    required this.input,
    required this.doubles,
  });

  final int roundNumber;
  final MiniGame game;

  /// The stable player ID of the chooser for this round.
  final String chooserId;

  /// Maps player ID → score delta for this round.
  final Map<String, int> scoresByPlayer;

  final Map<String, dynamic> input;
  final DoubleMatrix doubles;

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'gameName': game.name,
    'gameId': game.id,
    'chooserId': chooserId,
    'scores': scoresByPlayer,
    // Uniform persisted shape: a positional list of per-player count maps.
    'input': {'counts': game.inputToCounts(input)},
    if (doubles.hasAnyDouble) 'doublesJson': doubles.toJson(),
  };
}
