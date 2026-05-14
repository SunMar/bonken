import 'package:flutter/material.dart';

/// Compact pill used to surface a double/redouble state.
///
/// Shared between [DoublesChips] (the read-only summary on each round)
/// and `_TargetTile` in `doubles_picker.dart` (the interactive picker)
/// so both screens use exactly the same M3 [Chip] recipe — no border,
/// 4h `labelPadding`, zero outer padding, compact density, bold
/// `labelMedium` label. Background and foreground colors are passed in
/// because callers already resolve them from `DoubleStateColors`.
class DoubleStateChip extends StatelessWidget {
  const DoubleStateChip({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: foreground,
        fontWeight: FontWeight.bold,
      ),
      backgroundColor: background,
      side: BorderSide.none,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
