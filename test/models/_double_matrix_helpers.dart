import 'package:bonken/models/double_matrix.dart';

/// Test-only helpers for [DoubleMatrix].
extension DoubleMatrixTestHelpers on DoubleMatrix {
  /// Convenience for tests: set [state] for the pair, treating [playerA] as
  /// the initiator.
  DoubleMatrix withState(String playerA, String playerB, DoubleState state) =>
      withPair(playerA, playerB, state, initiator: playerA);
}
