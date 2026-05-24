import 'package:flutter/material.dart';

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
/// [SuitSymbol] renders as a card-suit glyph in DejaVu Sans (so the
/// glyph matches the launcher icons and isn't substituted for a colored
/// emoji on Android), and an [IconSymbol] renders as a Material Symbols
/// vector glyph sized to roughly match the cap height of adjacent text.
/// The `switch` arms below are intentionally ordered to match this doc.
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
        // Icon size matches the cap height of adjacent letters. Unlike
        // [Text], [Icon] does not honor the user's accessibility text
        // scale automatically, so we apply [MediaQuery.textScalerOf]
        // manually to keep icon and text avatars visually consistent.
        size: MediaQuery.textScalerOf(context).scale(fontSize) * 1.1,
        color: color,
        // `fill: 1` renders Material Symbols (a variable font) in their
        // filled variant.
        fill: 1,
      ),
      SuitSymbol(:final text) => Text(
        text,
        style: TextStyle(
          color: color,
          // Bundled DejaVu Sans, regular weight — matches the suits in
          // the launcher icons (rendered from the same .ttf by
          // tool/generate_icons.sh) and avoids Android substituting
          // colored emoji for these codepoints.
          fontFamily: 'DejaVu Sans',
          fontWeight: FontWeight.normal,
          // The suit glyphs in DejaVu Sans don't fill the em-box the way
          // letter glyphs do, so they look noticeably smaller than the
          // text variants at the same nominal size. Scale up so suit
          // glyphs read at the same visual weight as letter glyphs at
          // the same nominal `fontSize`. The user's accessibility text
          // scale is still applied automatically by [Text] on top of
          // this static design multiplier.
          fontSize: fontSize * 1.4,
        ),
      ),
    };
  }
}
