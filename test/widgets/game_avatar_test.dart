import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/screens/game_screen.dart';

import '_helpers.dart';

void main() {
  group('GameAvatar SuitSymbol rendering', () {
    // The SuitSymbol arm in `_GameSymbol` has two non-trivial design
    // decisions that aren't otherwise compile-time enforced:
    //   1. The glyph must be rendered with the bundled DejaVu Sans font
    //      (not the platform default), so suits match the launcher
    //      icons and Android can't substitute a colored emoji.
    //   2. The font size is multiplied by 1.4 to compensate for DejaVu
    //      Sans' suit glyphs not filling the em-box.
    // These tests guard against either being silently dropped.

    testWidgets('Hearts renders ♥ in DejaVu Sans at 1.4× the nominal size', (
      tester,
    ) async {
      await pumpHost(tester, const GameAvatar(game: Hearts(), radius: 24));

      final text = tester.widget<Text>(find.text('♥'));
      expect(text.style?.fontFamily, 'DejaVu Sans');
      // GameAvatar passes fontSize: 16 to _GameSymbol; SuitSymbol scales
      // by 1.4.
      expect(text.style?.fontSize, closeTo(16 * 1.4, 0.001));
      expect(text.style?.fontWeight, FontWeight.normal);
    });

    testWidgets('all four suit games render their glyph as a SuitSymbol', (
      tester,
    ) async {
      const cases = <(Widget, String)>[
        (GameAvatar(game: Clubs(), radius: 24), '♣'),
        (GameAvatar(game: Diamonds(), radius: 24), '♦'),
        (GameAvatar(game: Hearts(), radius: 24), '♥'),
        (GameAvatar(game: Spades(), radius: 24), '♠'),
      ];
      for (final (avatar, glyph) in cases) {
        await pumpHost(tester, avatar);
        final text = tester.widget<Text>(find.text(glyph));
        expect(
          text.style?.fontFamily,
          'DejaVu Sans',
          reason: 'suit glyph $glyph must use bundled DejaVu Sans',
        );
      }
    });
  });
}
