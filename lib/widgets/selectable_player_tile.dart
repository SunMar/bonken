import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'selectable_tile.dart';

/// A selectable player tile shared by [PlayerPicker] and the initiator panel
/// of [DoublesPicker]. Selection is shown via [secondaryContainer] fill;
/// [isDimmed] applies 38% opacity. An optional [badge] is shown trailing the
/// name (used by [DoublesPicker] to display the doubles involvement count).
///
/// A thin wrapper over the shared [SelectableTile] chrome, supplying the
/// selection decoration + name/badge row.
///
/// When [isDimmed] (another tile is selected) the tile is presented to
/// assistive tech as *disabled* — matching its dimmed look, so the 38%-opacity
/// text is WCAG contrast-exempt — while a `Selecteren` custom semantics action
/// keeps the switch-selection reachable. The visual `InkWell` tap is unchanged.
class SelectablePlayerTile extends StatelessWidget {
  const SelectablePlayerTile({
    required this.name,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
    this.badge,
    super.key,
  });

  final String name;
  final bool isSelected;

  /// True when another tile is selected — renders at 38% opacity but remains
  /// tappable to switch the selection.
  final bool isDimmed;
  final VoidCallback onTap;

  /// Optional trailing widget, typically a [Badge] with a doubles count.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Announce as a single selectable button (merges the name + optional badge
    // count). When dimmed (another tile selected), present as disabled so the
    // 38%-opacity text is contrast-exempt, but expose the switch via a
    // 'Selecteren' custom action; the visual InkWell tap still works.
    return SelectableTile(
      onTap: onTap,
      dimmed: isDimmed,
      selected: isSelected,
      enabled: isDimmed ? false : null,
      customSemanticsActions: isDimmed
          ? {const CustomSemanticsAction(label: 'Selecteren'): onTap}
          : null,
      // M3 selection convention (FilterChip, NavigationBar indicator): the
      // filled secondaryContainer IS the affordance; outline disappears once
      // selected.
      backgroundColor: isSelected ? cs.secondaryContainer : null,
      borderColor: isSelected ? Colors.transparent : cs.outlineVariant,
      children: [
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: tt.bodyMedium?.copyWith(
              color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        if (badge != null) ...[const SizedBox(width: 8), badge!],
      ],
    );
  }
}
