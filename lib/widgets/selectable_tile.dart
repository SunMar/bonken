import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

/// Shared animated selection-tile chrome used by `SelectablePlayerTile` (player
/// pickers + doubling initiators) and the doubles-picker target tiles. Owns the
/// `Padding`→`InkWell`→`AnimatedContainer`→`Row` scaffold (the 48dp-clearing
/// rhythm, the 150ms selection animation, the 8dp radius) and the
/// `MergeSemantics`→`Semantics(button)`→`Opacity` wrapper, so the two consumers
/// stay visually and accessibly in sync by construction rather than by comment.
///
/// Each consumer supplies only what differs: the [backgroundColor]/[borderColor]
/// for the `BoxDecoration`, the row [children], and the semantics flags. The
/// optional [selected]/[enabled]/[hint]/[customSemanticsActions] are passed
/// straight through (null = unspecified) so each tile keeps exactly the
/// semantics it had before extraction.
class SelectableTile extends StatelessWidget {
  const SelectableTile({
    required this.children,
    required this.backgroundColor,
    required this.borderColor,
    required this.dimmed,
    required this.onTap,
    this.selected,
    this.enabled,
    this.hint,
    this.customSemanticsActions,
    super.key,
  });

  /// Row content (the `Row` itself is part of the shared chrome).
  final List<Widget> children;

  /// Fill of the tile; `null` renders transparent.
  final Color? backgroundColor;

  /// Border colour (always a 1dp `Border.all`).
  final Color borderColor;

  /// Renders the tile at 38% opacity (purely visual; the tile stays tappable
  /// when [onTap] is non-null).
  final bool dimmed;

  /// Tap handler, or `null` for an inert tile.
  final VoidCallback? onTap;

  /// Passed straight to `Semantics.selected` (null = no selected state).
  final bool? selected;

  /// Passed straight to `Semantics.enabled` (null = no enabled state).
  final bool? enabled;

  /// Passed straight to `Semantics.hint`.
  final String? hint;

  /// Extra assistive-tech actions (e.g. a "Forceren" override exposed on a
  /// dimmed tile that is presented to AT as disabled).
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // M3 ListTile-equivalent rhythm: 16dp horizontal padding, sized to
          // clear the 48dp touch-target floor on top of bodyMedium (~20dp).
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(children: children),
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        hint: hint,
        customSemanticsActions: customSemanticsActions,
        child: dimmed ? Opacity(opacity: 0.38, child: tile) : tile,
      ),
    );
  }
}
