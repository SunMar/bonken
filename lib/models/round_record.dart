import 'double_matrix.dart';
import 'mini_game.dart';
import 'score_result.dart';

/// Stores everything about a completed round so it can be shown in history
/// and restored for editing if needed.
class RoundRecord {
  const RoundRecord({
    required this.roundNumber,
    required this.game,
    required this.dealerIndex,
    required this.chooserIndex,
    required this.input,
    required this.doubles,
    required this.result,
  });

  final int roundNumber;
  final MiniGame game;
  final int dealerIndex;
  final int chooserIndex;
  final Map<String, dynamic> input;
  final DoubleMatrix doubles;
  final ScoreResult result;
}
