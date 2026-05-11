import 'package:flutter/material.dart';

/// Colors used by warning/notice surfaces (amber callouts, rules notes).
///
/// Material 3's `ColorScheme` only ships primary / secondary / tertiary /
/// error.  There is no built-in "warning" semantic role — apps that need a
/// distinct cautionary surface (where `error` would be too alarming and
/// `tertiary` too subtle / branded) define their own via a [ThemeExtension].
///
/// The values stay in lock-step with the chosen seed colour by being read
/// from `Theme.of(context).extension<WarningColors>()` everywhere.
@immutable
class WarningColors extends ThemeExtension<WarningColors> {
  const WarningColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });

  /// Soft amber wash for the callout body.
  final Color background;

  /// Stronger amber for the 1dp box border (and rules-note left bar).
  final Color border;

  /// Default text colour when placed on [background].
  final Color foreground;

  /// Icon tint used for the warning glyph itself.
  final Color icon;

  static const light = WarningColors(
    background: Color(0x33FFD54F), // amber-300 @ ~20%
    border: Color(0xFFE6B800),
    foreground: Color(0xFF5D4200),
    icon: Color(0xFFB78103),
  );

  static const dark = WarningColors(
    background: Color(0x33FFB300), // amber-700 @ ~20%
    border: Color(0xFF8D6E00),
    foreground: Color(0xFFFFE082),
    icon: Color(0xFFFFCA28),
  );

  @override
  WarningColors copyWith({
    Color? background,
    Color? border,
    Color? foreground,
    Color? icon,
  }) => WarningColors(
    background: background ?? this.background,
    border: border ?? this.border,
    foreground: foreground ?? this.foreground,
    icon: icon ?? this.icon,
  );

  @override
  WarningColors lerp(ThemeExtension<WarningColors>? other, double t) {
    if (other is! WarningColors) return this;
    return WarningColors(
      background: Color.lerp(background, other.background, t)!,
      border: Color.lerp(border, other.border, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
    );
  }
}

/// Per-suit accent colours used by the `GameAvatar` and any other surface
/// that wants to evoke a specific playing-card suit.  These are fixed brand
/// colours (deliberately chosen to read as the four suits without resorting
/// to emoji), so they sit in a [ThemeExtension] rather than the seed-derived
/// `ColorScheme` — but go through `Theme.of(context)` so future user-themable
/// variants stay opt-in.
@immutable
class GameSuitColors extends ThemeExtension<GameSuitColors> {
  const GameSuitColors({
    required this.clubs,
    required this.spades,
    required this.diamonds,
    required this.hearts,
  });

  final Color clubs;
  final Color spades;
  final Color diamonds;
  final Color hearts;

  /// Returns the suit colour for a given mini-game id, or `null` if the
  /// game isn't tied to a specific suit (caller falls back to category
  /// accent).
  Color? forGameId(String id) => switch (id) {
    'clubs' => clubs,
    'spades' => spades,
    'diamonds' => diamonds,
    'hearts' => hearts,
    _ => null,
  };

  static const standard = GameSuitColors(
    clubs: Color(0xFF3A3A3A), // dark grey
    spades: Color(0xFF0D2B4E), // deep marine blue
    diamonds: Color(0xFFCC6600), // muted orange
    hearts: Color(0xFFB52424), // muted red
  );

  @override
  GameSuitColors copyWith({
    Color? clubs,
    Color? spades,
    Color? diamonds,
    Color? hearts,
  }) => GameSuitColors(
    clubs: clubs ?? this.clubs,
    spades: spades ?? this.spades,
    diamonds: diamonds ?? this.diamonds,
    hearts: hearts ?? this.hearts,
  );

  @override
  GameSuitColors lerp(ThemeExtension<GameSuitColors>? other, double t) {
    if (other is! GameSuitColors) return this;
    return GameSuitColors(
      clubs: Color.lerp(clubs, other.clubs, t)!,
      spades: Color.lerp(spades, other.spades, t)!,
      diamonds: Color.lerp(diamonds, other.diamonds, t)!,
      hearts: Color.lerp(hearts, other.hearts, t)!,
    );
  }
}

/// Background/foreground colours for the "doubled" and "redoubled" pair
/// states.
///
/// Both themes use hand-picked muted navy (doubled) and brick red
/// (redoubled) so the doubled state isn't tied to the brand hue and the
/// redoubled state isn't as saturated as the seeded `errorContainer`. The
/// values follow the M3 container recipe (tone-90 bg / tone-10 on-bg in
/// light mode, tone-30 bg / tone-90 on-bg in dark mode) at low chroma
/// (~16 in light, ~22 in dark) so the chips sit quietly next to the brand
/// indigo. Grouped into one extension so call sites have a single source
/// of truth without branching on [Brightness].
@immutable
class DoubleStateColors extends ThemeExtension<DoubleStateColors> {
  const DoubleStateColors({
    required this.doubledBackground,
    required this.onDoubledBackground,
    required this.redoubledBackground,
    required this.onRedoubledBackground,
  });

  final Color doubledBackground;
  final Color onDoubledBackground;
  final Color redoubledBackground;
  final Color onRedoubledBackground;

  /// Hand-picked muted navy / brick at the M3 tone-90/10 step.
  static const light = DoubleStateColors(
    doubledBackground: Color(0xFFDDE1FF),
    onDoubledBackground: Color(0xFF0F1A5E),
    redoubledBackground: Color(0xFFFFDBD7),
    onRedoubledBackground: Color(0xFF5E1310),
  );

  /// Hand-picked muted navy / brick at the M3 tone-30/90 step (the
  /// seed-derived containers are uncomfortably saturated on a dark
  /// surface).
  static const dark = DoubleStateColors(
    doubledBackground: Color(0xFF3A4370),
    onDoubledBackground: Color(0xFFE0E0FF),
    redoubledBackground: Color(0xFF703A39),
    onRedoubledBackground: Color(0xFFFFDBD7),
  );

  @override
  DoubleStateColors copyWith({
    Color? doubledBackground,
    Color? onDoubledBackground,
    Color? redoubledBackground,
    Color? onRedoubledBackground,
  }) => DoubleStateColors(
    doubledBackground: doubledBackground ?? this.doubledBackground,
    onDoubledBackground: onDoubledBackground ?? this.onDoubledBackground,
    redoubledBackground: redoubledBackground ?? this.redoubledBackground,
    onRedoubledBackground: onRedoubledBackground ?? this.onRedoubledBackground,
  );

  @override
  DoubleStateColors lerp(ThemeExtension<DoubleStateColors>? other, double t) {
    if (other is! DoubleStateColors) return this;
    return DoubleStateColors(
      doubledBackground: Color.lerp(
        doubledBackground,
        other.doubledBackground,
        t,
      )!,
      onDoubledBackground: Color.lerp(
        onDoubledBackground,
        other.onDoubledBackground,
        t,
      )!,
      redoubledBackground: Color.lerp(
        redoubledBackground,
        other.redoubledBackground,
        t,
      )!,
      onRedoubledBackground: Color.lerp(
        onRedoubledBackground,
        other.onRedoubledBackground,
        t,
      )!,
    );
  }
}

/// Semantic colours for player scores.
///
/// Positive scores are tinted green and negative scores red — but neither
/// fits an existing M3 role: `cs.primary` ties "good number" to the brand
/// hue, and `cs.error` overloads error semantics with a value that's just
/// negative, not actually wrong. Hence a dedicated extension.
///
/// Light and dark mode use M3 tone-40 / tone-80 pairs, mirroring the
/// way M3 derives its own `error` role across brightness — same hue,
/// shifted tone, balanced contrast on the surrounding surface.
@immutable
class ScoreColors extends ThemeExtension<ScoreColors> {
  const ScoreColors({required this.positive, required this.negative});

  /// Tint for scores > 0 and "good" accents (e.g. positive game category).
  final Color positive;

  /// Tint for scores < 0 and "bad" accents (e.g. negative game category).
  /// Deliberately distinct from the redouble brick red so the two
  /// semantics don't blur together.
  final Color negative;

  /// Score == 0 falls back to the surrounding theme's `onSurfaceVariant`
  /// (the standard "muted body text" tone), so it isn't carried here.
  static const light = ScoreColors(
    positive: Color(0xFF2A7D55), // cool green, M3 tone-40 band
    negative: Color(0xFFD32F2F), // warm red, M3 tone-40 band
  );

  static const dark = ScoreColors(
    positive: Color(0xFF7AD3A3), // cool green, M3 tone-80 band
    negative: Color(0xFFFFA89E), // warm red, M3 tone-80 band
  );

  @override
  ScoreColors copyWith({Color? positive, Color? negative}) => ScoreColors(
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
  );

  @override
  ScoreColors lerp(ThemeExtension<ScoreColors>? other, double t) {
    if (other is! ScoreColors) return this;
    return ScoreColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
    );
  }
}
