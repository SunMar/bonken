import 'package:flutter/foundation.dart';

import '../utils.dart';
import 'hearts_variant.dart';
import 'starter_variant.dart';

/// The set of per-game rule variants chosen for a session, grouped into one
/// value object.
///
/// Grouping keeps the persisted shape (the `ruleVariants` JSON key) aligned
/// with the in-memory domain model ([GameSession] and `CalculatorState` both
/// carry a single [RuleVariants]), and means a future rule variant is added
/// here once instead of being threaded through every call site.
///
/// There is no canonical Bonken rule set — the default values are just the
/// technical seeds used until the player (or a loaded session) supplies their
/// own; they are not an imposed standard.
@immutable
class RuleVariants {
  const RuleVariants({
    this.starterVariant = .dealerStarts,
    this.heartsVariant = .onlyAfterPlayedHeart,
  });

  /// Which player leads the first trick of each round.
  final StarterVariant starterVariant;

  /// Hearts-lead restriction in effect for the game.
  final HeartsVariant heartsVariant;

  RuleVariants copyWith({
    StarterVariant? starterVariant,
    HeartsVariant? heartsVariant,
  }) => RuleVariants(
    starterVariant: starterVariant ?? this.starterVariant,
    heartsVariant: heartsVariant ?? this.heartsVariant,
  );

  Map<String, dynamic> toJson() => {
    'starterVariant': starterVariant.name,
    'heartsVariant': heartsVariant.name,
  };

  /// Reads a [RuleVariants] from a stored map. An **absent** entry falls back
  /// to its default; a **present-but-unrecognized** value throws (corrupt or
  /// forward-version data is rejected at the storage/import boundary, not
  /// silently coerced). Storage is always migrated to the nested shape before
  /// this runs — see `migrations.dart`.
  factory RuleVariants.fromJson(Map<String, dynamic> json) => RuleVariants(
    starterVariant: enumByName(
      StarterVariant.values,
      json['starterVariant'] as String?,
      StarterVariant.dealerStarts,
    ),
    heartsVariant: enumByName(
      HeartsVariant.values,
      json['heartsVariant'] as String?,
      HeartsVariant.onlyAfterPlayedHeart,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is RuleVariants &&
      other.starterVariant == starterVariant &&
      other.heartsVariant == heartsVariant;

  @override
  int get hashCode => Object.hash(starterVariant, heartsVariant);
}
