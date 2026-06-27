import 'dart:math' as math;

import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // GameAvatar paints the suit colour both as its symbol (full strength) and as
  // its background (the same colour at 12% over the surface), so the contrast
  // that matters is the glyph against that wash. Every suit must clear the WCAG
  // 1.4.11 graphical-object floor (3:1) on both the plain surface and a card
  // (surfaceContainer), in both themes. This guards the dark palette (deep
  // navy spade / near-black club were ~1.3:1 before it existed) and the light
  // diamonds nudge (was 2.90:1 on a card).
  const palettes = {
    Brightness.light: GameSuitColors.light,
    Brightness.dark: GameSuitColors.dark,
  };

  // `colorSchemeSeed: Colors.indigo` in the app theme resolves to exactly this.
  ColorScheme schemeFor(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness);

  palettes.forEach((brightness, suits) {
    final cs = schemeFor(brightness);
    final byName = {
      'clubs': suits.clubs,
      'spades': suits.spades,
      'diamonds': suits.diamonds,
      'hearts': suits.hearts,
    };
    final backgrounds = {
      'surface': cs.surface,
      'surfaceContainer': cs.surfaceContainer,
    };

    byName.forEach((suit, color) {
      backgrounds.forEach((bgName, bg) {
        test('$brightness $suit glyph clears 3:1 on $bgName', () {
          // The avatar background is the suit colour at 12% over the surface;
          // the glyph is the suit colour at full strength on top of it.
          final avatarBg = Color.alphaBlend(color.withValues(alpha: 0.12), bg);
          expect(_contrast(color, avatarBg), greaterThanOrEqualTo(3.0));
        });
      });
    });
  });
}
