import 'package:flutter/material.dart';

import '../models/double_matrix.dart';

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

  /// Resolves from the ambient theme, falling back to the brightness-appropriate
  /// static when the extension isn't registered (e.g. unthemed test widgets).
  static WarningColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<WarningColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

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
///
/// ## Why a separate dark variant
///
/// `GameAvatar` paints the suit colour both as its symbol (full strength) and
/// as its background (the *same* colour at 12% over the surface), so the
/// contrast that matters is the glyph against that wash. The [light] palette is
/// hand-tuned to read on a near-white surface, and several of its colours are
/// deliberately dark (deep navy spade, near-black club, brick heart) — good on
/// light, but near-invisible on the dark surface (`#121318`), where spade/club
/// drop to ~1.3:1. [dark] re-tunes each suit for that surface.
///
/// ## Why these specific hex values
///
/// Chosen in **HCT** (hue-chroma-tone — Material 3's perceptually uniform
/// space; see Google's `material_color_utilities`). [dark] keeps each suit's
/// [light] hue and picks, *per suit*, the lowest tone that still clears a
/// comfortable ≥4.5:1 for the glyph against its avatar background — a lower
/// tone retains more of the suit's chroma, i.e. its character:
///
/// * **clubs** — neutral grey (C≈1.5), so tone is a pure contrast/appearance
///   call: `T 74`, a clean light grey (the dark-inversion of light's dark grey).
/// * **spades** — blue holds its chroma (C≈30) at any tone, so `T 70` keeps a
///   rich periwinkle instead of a pale wash.
/// * **diamonds** — orange holds its signature high chroma (C≈59) only down to
///   ~`T 70`; higher tones flatten it to a pale peach.
/// * **hearts** — red can't hold C≈77 in dark at all (sRGB gamut), but `T 66`
///   recovers C≈61 *and* pulls it clear of [ScoreColors.dark]'s negative red
///   (also `T 70`) that a `T 70` heart would have collided with.
///
/// The lone [light] tweak: diamonds is `#BB5D00` (`T 50`), not the original
/// `#CC6600` (`T 54`) — the latter dipped to 2.90:1 on a card
/// (`surfaceContainer`), just under the 3:1 graphical-object floor.
///
/// To explore alternatives: `fvm dart run tool/hct.dart from H,C,T ...`
/// (or `to RRGGBB ...` for the inverse).
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

  /// Hand-tuned for a near-white surface (HCT shown alongside each value).
  static const light = GameSuitColors(
    clubs: Color(0xFF3A3A3A), // dark grey,         H 210 / C  1 / T 24
    spades: Color(0xFF0D2B4E), // deep marine blue, H 260 / C 30 / T 17
    diamonds: Color(0xFFBB5D00), // muted orange,   H  53 / C 56 / T 50
    hearts: Color(0xFFB52424), // muted red,        H  24 / C 77 / T 40
  );

  /// Re-tuned per suit for the dark surface — see the class doc for the recipe.
  static const dark = GameSuitColors(
    clubs: Color(0xFFB7B6B5), // light grey,      H 210 / C  2 / T 74
    spades: Color(0xFF93ACD7), // periwinkle,     H 260 / C 30 / T 70
    diamonds: Color(0xFFFF8E34), // vivid orange, H  53 / C 59 / T 70
    hearts: Color(0xFFFF766C), // coral red,      H  24 / C 61 / T 66
  );

  /// Resolves from the ambient theme, falling back to the brightness-appropriate
  /// static when the extension isn't registered (e.g. unthemed test widgets).
  static GameSuitColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GameSuitColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

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

  /// Resolves from the ambient theme, falling back to the brightness-appropriate
  /// static when the extension isn't registered.
  static DoubleStateColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<DoubleStateColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  /// Background for a pair [state]; `null` for [DoubleState.none] (no fill).
  Color? backgroundFor(DoubleState state) => switch (state) {
    .none => null,
    .doubled => doubledBackground,
    .redoubled => redoubledBackground,
  };

  /// Foreground (on-background) for a pair [state]; `null` for
  /// [DoubleState.none].
  Color? foregroundFor(DoubleState state) => switch (state) {
    .none => null,
    .doubled => onDoubledBackground,
    .redoubled => onRedoubledBackground,
  };

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
/// ## Why these specific hex values
///
/// The pairs were chosen in **HCT** (hue-chroma-tone — Material 3's
/// perceptually uniform colour space; see Google's `material_color_utilities`
/// package) rather than picked from a swatch, so positive and negative read
/// as equally weighted instead of one shouting over the other.
///
/// Recipe:
///
/// * **Hue** — `162°` (cool green) and `18°` (warm red). Roughly opposite
///   on the HCT wheel, both shifted slightly off pure primary so they
///   harmonise with the cool indigo seed of the rest of the app.
/// * **Tone** — M3's accent bands: `T 45` for light mode, `T 70` for dark.
///   (Pure M3 uses 40/80; we nudged inward because the 40/80 pair tested
///   slightly washed-out on phone hardware vs. desktop sRGB.)
/// * **Chroma** — matched within each theme (`C 45` light, `C 50` dark) so
///   the two colours carry the same visual weight. Pure red can go far
///   higher in chroma than pure green at these tones in sRGB, but pushing
///   red to its ceiling makes it feel like an alert — exactly the
///   `cs.error` overload we wanted to avoid.
///
/// To explore alternatives: `dart run tool/hct.dart from H,C,T ...`
/// (or `to RRGGBB ...` for the inverse).
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
    positive: Color(0xFF0C7A4F), // cool green, H 162 / C 45 / T 45
    negative: Color(0xFFA84F52), // warm red,  H  18 / C 45 / T 45
  );

  static const dark = ScoreColors(
    positive: Color(0xFF50BF89), // cool green, H 162 / C 50 / T 70
    negative: Color(0xFFFE898B), // warm red,  H  18 / C 50 / T 70
  );

  /// Resolves from the ambient theme, falling back to the brightness-appropriate
  /// static when the extension isn't registered (e.g. unthemed test widgets).
  static ScoreColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ScoreColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

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

// ---------------------------------------------------------------------------
// Shared theme builders
// ---------------------------------------------------------------------------

/// Returns [base] with an [IconButtonThemeData] that tints icon buttons with
/// [foregroundColor] so they fade into a muted row (date headers, session
/// cards) without per-button overrides. Keeps the standard Material 48dp
/// tap target (a11y) — no size/density shrink.
ThemeData mutedIconButtonTheme(ThemeData base, {Color? foregroundColor}) {
  return base.copyWith(
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: foregroundColor),
    ),
  );
}

// ---------------------------------------------------------------------------
// Theme value helpers
// ---------------------------------------------------------------------------

/// True when the ambient theme is dark. Centralises the `Brightness.dark`
/// check shared by the [ThemeExtension] `of` fallbacks (and any other
/// brightness-dependent default).
bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Tint for a player's cumulative or per-round score, based on its sign.
///
/// Reads the [ScoreColors] theme extension; falls back to the
/// brightness-appropriate static if unavailable (e.g. unthemed test
/// widgets).
Color scoreColor(int score, BuildContext context) {
  if (score == 0) return _scoreColorNeutral(context);
  return score > 0 ? scoreColorPositive(context) : scoreColorNegative(context);
}

Color scoreColorPositive(BuildContext context) =>
    ScoreColors.of(context).positive;
Color scoreColorNegative(BuildContext context) =>
    ScoreColors.of(context).negative;
Color _scoreColorNeutral(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Material 3 disabled-content color: `onSurface` at 38% alpha.
///
/// `0.38` is the official M3 disabled-content opacity from the spec
/// (m3.material.io → states → disabled). Use this for text, icons and
/// other foreground content drawn on top of a surface when their
/// associated control is disabled. Centralised so the alpha value isn't
/// sprinkled across screens.
Color disabledOnSurface(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.38);

/// Shared [MenuItemButton] / [SubmenuButton] style for menu anchors.
///
/// Adds 16 px of horizontal padding so the [TextButton]-derived
/// [MenuItemButton] gets a comfortable popup-menu rhythm instead of its
/// default tight padding. Referenced by the theme menu (`ThemeMenuButton`) and
/// any future [MenuAnchor], so their item density stays in sync.
final ButtonStyle kMenuItemButtonStyle = MenuItemButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 16),
);
