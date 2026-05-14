import 'package:flutter/material.dart';

/// A single-selection player picker: shows [prompt] above the four players
/// rendered as tiles that visually match the initiator tiles in the
/// doubles picker (see `_InitiatorTile` in `doubles_picker.dart`) so the
/// "pick a player" affordance looks identical wherever it appears.
/// Exactly one player can be selected (or none, when [selectedIndex] is
/// `null`).
class PlayerPicker extends StatelessWidget {
  const PlayerPicker({
    required this.playerNames,
    required this.selectedIndex,
    required this.prompt,
    required this.onSelected,
    super.key,
  });

  final List<String> playerNames;
  final int? selectedIndex;
  final String prompt;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        for (int i = 0; i < playerNames.length; i++)
          _PlayerTile(
            name: playerNames[i],
            isSelected: selectedIndex == i,
            isDimmed: selectedIndex != null && selectedIndex != i,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

/// Visual twin of `_InitiatorTile` in `doubles_picker.dart`. Kept as a
/// private copy (rather than extracted to a shared widget) so each picker
/// can evolve its own per-tile decoration — the doubles initiator carries
/// an involvement [Badge] that has no meaning here.
class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.name,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
  });

  final String name;
  final bool isSelected;

  /// True when another tile is selected — this tile renders at 38%
  /// opacity but remains tappable to switch the selection.
  final bool isDimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // M3 ListTile-equivalent rhythm: 16h horizontal padding, with
          // vertical sized to clear the 48dp touch-target floor on top
          // of a single line of bodyMedium (~20dp).
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            // M3 selection convention (FilterChip, NavigationBar
            // indicator): the filled secondaryContainer IS the
            // affordance; the outline disappears once selected.
            border: Border.all(
              color: isSelected ? Colors.transparent : cs.outlineVariant,
            ),
          ),
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
    return isDimmed ? Opacity(opacity: 0.38, child: tile) : tile;
  }
}
