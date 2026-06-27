import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/games/positive_games.dart';
import 'package:bonken/theme/app_theme_extensions.dart';
import 'package:bonken/widgets/game_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '_helpers.dart';

void main() {
  group('GameAvatar SuitSymbol rendering', () {
    // The SuitSymbol arm in `_GameSymbol` has two non-trivial design
    // decisions that aren't otherwise compile-time enforced:
    //   1. The glyph must be rendered with the bundled Arimo font (via
    //      GoogleFonts.arimo(), not the platform default), so suits match
    //      the launcher icons and Android can't substitute a colored
    //      emoji. GoogleFonts encodes the family as 'Arimo_<variant>'.
    //   2. The font size is multiplied by 2.0 to scale the suit glyphs up
    //      so they visually fill the avatar.
    // These tests guard against either being silently dropped.

    testWidgets('Hearts renders ♥ in Arimo at 2.0× the nominal size', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHost(tester, const GameAvatar(game: Hearts(), radius: 24));

      final text = tester.widget<Text>(find.text('♥'));
      expect(text.style?.fontFamily, contains('Arimo'));
      // GameAvatar passes fontSize: 16 to _GameSymbol; SuitSymbol scales
      // by 2.0.
      expect(text.style?.fontSize, closeTo(16 * 2.0, 0.001));
      expect(text.style?.fontWeight, FontWeight.normal);
      // The decorative suit glyph is kept out of the a11y tree (the game name
      // is announced by the surrounding tile, not this avatar).
      expect(find.bySemanticsLabel('♥'), findsNothing);
      handle.dispose();
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
          contains('Arimo'),
          reason: 'suit glyph $glyph must use bundled Arimo',
        );
      }
    });
  });

  group('GameAvatar symbol arms (text + icon)', () {
    testWidgets(
      'TextSymbol renders its bold label but excludes it from semantics',
      (tester) async {
        final handle = tester.ensureSemantics();
        // KingOfHearts uses TextSymbol('HH').
        await pumpHost(
          tester,
          const GameAvatar(game: KingOfHearts(), radius: 24),
        );

        final text = tester.widget<Text>(find.text('HH'));
        expect(text.style?.fontWeight, FontWeight.bold);
        expect(text.style?.fontSize, 16);
        // Decorative label is not announced before the real game name.
        expect(find.bySemanticsLabel('HH'), findsNothing);
        handle.dispose();
      },
    );

    testWidgets('IconSymbol renders its glyph (already decorative)', (
      tester,
    ) async {
      // Duck uses IconSymbol(Symbols.keyboard_double_arrow_down). An Icon with
      // no semanticLabel is excluded from the a11y tree for free, so the arm
      // only needs to prove the glyph renders.
      await pumpHost(tester, const GameAvatar(game: Duck(), radius: 24));

      final icon = tester.widget<Icon>(
        find.byIcon(Symbols.keyboard_double_arrow_down),
      );
      expect(icon.icon, Symbols.keyboard_double_arrow_down);
      expect(icon.fill, 1);
      expect(icon.semanticLabel, isNull);
    });
  });

  group('GameAvatar disabled branch', () {
    CircleAvatar avatarOf(WidgetTester tester) =>
        tester.widget<CircleAvatar>(find.byType(CircleAvatar));

    testWidgets('disabled dims the glyph and the background', (tester) async {
      await pumpHost(
        tester,
        const GameAvatar(game: KingOfHearts(), radius: 24, disabled: true),
      );
      final cs = Theme.of(tester.element(find.byType(GameAvatar))).colorScheme;

      // Background drops to the dimmer 0.06 alpha …
      expect(avatarOf(tester).backgroundColor?.a, closeTo(0.06, 0.001));
      // … and the glyph uses the muted disabled-on-surface colour.
      expect(
        tester.widget<Text>(find.text('HH')).style?.color,
        disabledOnSurface(cs),
      );
    });

    testWidgets('enabled uses the full 0.12 background alpha', (tester) async {
      await pumpHost(
        tester,
        const GameAvatar(game: KingOfHearts(), radius: 24),
      );
      expect(avatarOf(tester).backgroundColor?.a, closeTo(0.12, 0.001));
    });
  });
}
