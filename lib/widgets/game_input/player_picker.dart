import 'package:flutter/material.dart';

import '../selectable_player_tile.dart';

/// A single-selection player picker: shows [prompt] above the four players
/// rendered as tiles that visually match the initiator tiles in the
/// doubles picker (see `_InitiatorTile` in `doubles_picker.dart`) so the
/// "pick a player" affordance looks identical wherever it appears.
/// Exactly one player can be selected (or none, when [selectedIndex] is
/// `null`). Tapping the already-selected tile clears the selection (emits
/// `null`), mirroring the doubles initiator list's toggle behaviour.
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

  /// Called with the tapped index, or `null` when the currently-selected tile
  /// is tapped again (deselect).
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        for (int i = 0; i < playerNames.length; i++)
          SelectablePlayerTile(
            name: playerNames[i],
            isSelected: selectedIndex == i,
            isDimmed: selectedIndex != null && selectedIndex != i,
            onTap: () => onSelected(selectedIndex == i ? null : i),
          ),
      ],
    );
  }
}
