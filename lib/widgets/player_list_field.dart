import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/mini_game.dart';
import 'drag_handle.dart';
import 'player_name_field.dart';

/// A reorderable list of 4 [PlayerNameField] rows with drag handles, plus an
/// inline "two players have the same name" warning row when duplicates are
/// detected (case-insensitive).
///
/// Holds no state itself — the parent owns [controllers] and [focusNodes],
/// reorders them on [onReorder], and feeds new [takenNamesFor] / suggestions
/// after every keystroke.
class PlayerListField extends StatelessWidget {
  const PlayerListField({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.suggestions,
    required this.onReorder,
    required this.onSubmitted,
  }) : assert(controllers.length == playerCount),
       assert(focusNodes.length == playerCount);

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final List<String> suggestions;

  /// Same convention as [ReorderableListView.onReorder].
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Called when the user presses Enter on field [index].
  final void Function(int index) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final trimmedNames = [for (final c in controllers) c.text.trim()];
    final lowerNames = trimmedNames.map((n) => n.toLowerCase()).toList();
    final nonEmptyLower = lowerNames.where((n) => n.isNotEmpty).toList();
    final hasDuplicates =
        nonEmptyLower.length != nonEmptyLower.toSet().length;

    // Pre-compute the per-row "names taken by other slots" sets once instead
    // of allocating a fresh Set inside the loop body for every rebuild.
    final allNonEmpty = <String>{
      for (final n in trimmedNames)
        if (n.isNotEmpty) n,
    };
    final takenForRow = <Set<String>>[
      for (int i = 0; i < playerCount; i++)
        trimmedNames[i].isEmpty
            ? allNonEmpty
            : (Set<String>.from(allNonEmpty)..remove(trimmedNames[i])),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: onReorder,
          children: [
            for (int i = 0; i < playerCount; i++)
              Padding(
                key: ValueKey(focusNodes[i]),
                padding: EdgeInsets.only(bottom: i < playerCount - 1 ? 12 : 0),
                child: Row(
                  children: [
                    DragHandle(index: i),
                    Expanded(
                      child: PlayerNameField(
                        index: i,
                        controller: controllers[i],
                        focusNode: focusNodes[i],
                        suggestions: suggestions,
                        takenNames: takenForRow[i],
                        onSubmitted: () => onSubmitted(i),
                        isLast: i == playerCount - 1,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (hasDuplicates) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Symbols.warning_amber,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text(
                'Twee spelers hebben dezelfde naam.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Dropdown that picks the dealer slot. Items are labelled with each player's
/// trimmed controller text, falling back to "Speler N" when empty.
///
/// When [onClear] is provided AND [value] is non-null, a small (X) suffix
/// button appears that calls it (used in SetupScreen to undo a manual choice
/// and revert to the random-dealer hint).
class DealerDropdownField extends StatelessWidget {
  const DealerDropdownField({
    super.key,
    required this.controllers,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.onClear,
  }) : assert(controllers.length == playerCount);

  final List<TextEditingController> controllers;
  final int? value;
  final ValueChanged<int> onChanged;
  final String? hintText;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final showClear = onClear != null && value != null;
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: hintText,
        suffixIcon: showClear
            ? IconButton(
                icon: const Icon(Symbols.clear),
                tooltip: 'Wissen (willekeurige deler)',
                onPressed: onClear,
              )
            : null,
      ),
      items: [
        for (int i = 0; i < playerCount; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              controllers[i].text.trim().isNotEmpty
                  ? controllers[i].text
                  : 'Speler ${i + 1}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Shared "Enter pressed in slot [index]" handler.
///
/// If the next slot exists and is still empty, focuses it; otherwise
/// unfocuses the current field so the on-screen keyboard hides.
void handlePlayerFieldSubmitted({
  required int index,
  required List<TextEditingController> controllers,
  required List<FocusNode> focusNodes,
}) {
  final next = index + 1;
  if (next < playerCount && controllers[next].text.trim().isEmpty) {
    focusNodes[next].requestFocus();
    return;
  }
  focusNodes[index].unfocus();
}
