import 'package:flutter/material.dart';

/// A selectable player tile shared by [PlayerPicker] and the initiator panel
/// of [DoublesPicker]. Selection is shown via [secondaryContainer] fill;
/// [isDimmed] applies 38% opacity. An optional [badge] is shown trailing the
/// name (used by [DoublesPicker] to display the doubles involvement count).
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

    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // M3 ListTile-equivalent rhythm: 16dp horizontal padding, sized
          // to clear the 48dp touch-target floor on top of bodyMedium (~20dp).
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            // M3 selection convention (FilterChip, NavigationBar indicator):
            // the filled secondaryContainer IS the affordance; outline
            // disappears once selected.
            border: Border.all(
              color: isSelected ? Colors.transparent : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
            ],
          ),
        ),
      ),
    );
    return isDimmed ? Opacity(opacity: 0.38, child: tile) : tile;
  }
}
