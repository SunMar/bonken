import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Transient "flash this game in the home list" signal.
///
/// Set when the QR scanner declines an overwrite and returns to Home so the user
/// can find (and, if they want, open to compare) the existing game. The home
/// history list consumes it once — scroll-to + a brief highlight pulse — and then
/// [clear]s it, so it never re-fires on the next rebuild.
final highlightGameProvider = NotifierProvider<HighlightGameNotifier, String?>(
  HighlightGameNotifier.new,
);

class HighlightGameNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Request a one-shot highlight of the game with [gameId].
  void flash(String gameId) => state = gameId;

  /// Clear the signal after the home list has consumed it.
  void clear() => state = null;
}
