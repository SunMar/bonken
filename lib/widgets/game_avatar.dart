import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/mini_game.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';

/// Circular avatar showing a mini-game's symbol with its accent color.
class GameAvatar extends StatelessWidget {
  const GameAvatar({
    required this.game,
    required this.radius,
    this.disabled = false,
    super.key,
  });

  final MiniGame game;
  final double radius;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suits = GameSuitColors.of(context);
    final isPositive = game.category == GameCategory.positive;
    final textColor = scoreColor(isPositive ? 1 : -1, context);
    final symbolColor = suits.forGameId(game.id) ?? textColor;
    // [CircleAvatar] wraps its child in [MediaQuery.withNoTextScaling], so
    // the avatar and its contents do not scale with the accessibility text scale.
    return CircleAvatar(
      radius: radius,
      backgroundColor: symbolColor.withValues(alpha: disabled ? 0.06 : 0.12),
      child: _GameSymbol(
        symbol: game.symbol,
        color: disabled ? disabledOnSurface(cs) : symbolColor,
        fontSize: 16,
      ),
    );
  }
}

/// Renders a [GameSymbol]: a [TextSymbol] renders as bold text, a
/// [SuitSymbol] renders as a card-suit glyph in Arimo (so the
/// glyph matches the launcher icons and isn't substituted for a colored
/// emoji on Android), and an [IconSymbol] renders as a Material Symbols
/// vector glyph. Both [SuitSymbol] and [IconSymbol] are scaled above
/// [fontSize] so their ink fills the avatar.
class _GameSymbol extends StatelessWidget {
  const _GameSymbol({
    required this.symbol,
    required this.color,
    required this.fontSize,
  });

  final GameSymbol symbol;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Sealed-class switch: adding a fourth [GameSymbol] variant in the
    // model layer would make this expression fail to compile until a
    // branch is added here, which is the whole point of the sealed-class
    // refactor.
    return switch (symbol) {
      TextSymbol(:final text) => Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
      IconSymbol(:final icon) => Icon(
        icon,
        // [Icon.size] is the full bounding box; Material Symbols glyphs don't
        // fill it edge-to-edge. Scale above [fontSize] so the icon visually
        // fills the avatar rather than reading as a smaller inline glyph.
        size: fontSize * 1.35,
        color: color,
        // `fill: 1` renders Material Symbols (a variable font) in their
        // filled variant.
        fill: 1,
      ),
      SuitSymbol(:final text) => Builder(
        builder: (context) {
          // Arimo's suit glyphs don't fill the em-box the way letter glyphs
          // do, so they look noticeably smaller at the same nominal size.
          // Scale up so the suit visually fills the avatar.
          final suitFontSize = fontSize * 2.0;
          return Transform.translate(
            // Suit glyphs are shorter than capitals (ink heights 1122–1231 vs
            // cap height 1409 in Arimo, upem 2048). Both sit on the baseline,
            // so the height difference pushes the suit's ink centre below the
            // line-box centre. Font metric analysis predicts ~0.05; pixel
            // measurements confirm 0.10 is correct. The ~2× gap is likely due
            // to Flutter's line-box height exceeding what sTypo metrics alone
            // predict, shifting the baseline further from the widget centre.
            offset: Offset(0, -suitFontSize * 0.10),
            child: Text(
              text,
              // Bundled Arimo, regular weight — loaded offline via the
              // google_fonts package (same mechanism as the app's Roboto
              // text theme). Matches the suits in the launcher icons
              // (rendered from the same .ttf by tool/generate_icons.sh) and
              // avoids Android substituting colored emoji for these
              // codepoints.
              style: GoogleFonts.arimo(
                color: color,
                fontWeight: FontWeight.normal,
                fontSize: suitFontSize,
              ),
            ),
          );
        },
      ),
    };
  }
}
