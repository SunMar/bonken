import 'player.dart';

/// The typed, in-memory input for a single round.
///
/// Two variants, one per input shape:
///   - [CountsInput] — a per-player count map (tricks / scoring cards won).
///   - [RecipientInput] — a positional list of player UUIDs, one per prompt
///     slot (null when unfilled).
///
/// Using a sealed class gives exhaustive switch checking at compile time and
/// eliminates the need for string keys in the in-memory representation.
sealed class GameInput {
  const GameInput();

  /// Deep copy. Both variants hold mutable collections by reference, so a
  /// shallow copy is insufficient when capturing original state for edit-change
  /// detection.
  GameInput copy();
}

/// In-memory input for counts-style games: a per-player tally of tricks or
/// scoring cards won.
class CountsInput extends GameInput {
  const CountsInput(this.counts);

  /// Maps player UUID → count for this round.
  final Map<String, int> counts;

  @override
  CountsInput copy() => CountsInput(Map<String, int>.from(counts));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CountsInput) return false;
    if (counts.length != other.counts.length) return false;
    for (final e in counts.entries) {
      if (other.counts[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    counts.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// In-memory input for recipient-style games: one player UUID per prompt slot
/// (null when the slot is not yet filled).
class RecipientInput extends GameInput {
  const RecipientInput(this.recipients);

  /// One UUID per prompt slot; null when the slot is unfilled.
  final List<String?> recipients;

  @override
  RecipientInput copy() => RecipientInput(List<String?>.from(recipients));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RecipientInput) return false;
    if (recipients.length != other.recipients.length) return false;
    for (int i = 0; i < recipients.length; i++) {
      if (recipients[i] != other.recipients[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(recipients);
}

/// Describes the input fields required by a mini-game so the UI can render
/// the correct form without knowing concrete game types.
sealed class InputDescriptor {
  const InputDescriptor();

  /// True when [input] contains no meaningful entry yet.
  bool isEmpty(GameInput input);

  /// True when [input] is fully and validly filled in for this descriptor.
  bool isComplete(GameInput input);

  /// Initial input used when a game is freshly selected.
  GameInput defaults(List<Player> players);
}

/// A mini-game where each of the 4 players enters a count (tricks or scoring
/// cards won). The four values must sum to [total].
class CountsInputDescriptor extends InputDescriptor {
  const CountsInputDescriptor({required this.total, required this.unitLabel});

  /// Required sum of all four player counts.
  final int total;

  /// Human-readable unit shown next to the count (Dutch, e.g. 'slagen').
  final String unitLabel;

  @override
  bool isEmpty(GameInput input) {
    final counts = (input as CountsInput).counts;
    return counts.values.fold<int>(0, (a, b) => a + b) == 0;
  }

  @override
  bool isComplete(GameInput input) {
    final counts = (input as CountsInput).counts;
    return counts.values.fold<int>(0, (a, b) => a + b) == total;
  }

  @override
  GameInput defaults(List<Player> players) =>
      CountsInput({for (final p in players) p.id: 0});
}

/// A mini-game where one or more players are identified as recipients of an
/// outcome (a trick won, a card taken, etc.). Each slot in [prompts]
/// corresponds to one independent player selection.
class RecipientInputDescriptor extends InputDescriptor {
  const RecipientInputDescriptor({required this.prompts});

  /// Questions shown above each player selector (Dutch), one per slot.
  final List<String> prompts;

  @override
  bool isEmpty(GameInput input) {
    final recipients = (input as RecipientInput).recipients;
    return recipients.every((v) => v == null);
  }

  @override
  bool isComplete(GameInput input) {
    final recipients = (input as RecipientInput).recipients;
    if (recipients.length != prompts.length) return false;
    return recipients.every((v) => v != null && v.isNotEmpty);
  }

  @override
  GameInput defaults(List<Player> players) =>
      RecipientInput(List<String?>.filled(prompts.length, null));
}
