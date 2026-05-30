import 'package:flutter/material.dart';

/// A horizontally-wrapping `label: value  ·  label: value  ·  …` metadata line.
///
/// Shared by the in-game round banners (`_RoundInfoBanner` on the game screen
/// and `_RoundInputHeader` on the round-input screen) to show the
/// Kiezer / Deler / Uitkomst trio. [segments] are rendered in order over
/// `bodyMedium` in [color]; the `·` separator is attached to the preceding
/// segment so a wrapped line never starts with an orphaned separator.
class RoundMetaLine extends StatelessWidget {
  const RoundMetaLine({super.key, required this.segments, required this.color});

  /// Ordered `label: value` strings, e.g. `'Kiezer: Alice'`.
  final List<String> segments;

  /// Text colour — varies per host (banner vs. header background).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color);
    return Wrap(
      children: [
        for (var i = 0; i < segments.length; i++)
          Text(
            i == segments.length - 1 ? segments[i] : '${segments[i]}  ·  ',
            style: style,
          ),
      ],
    );
  }
}
