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
/// reorders them on [onReorderItem], and feeds new [takenNamesFor] / suggestions
/// after every keystroke.
class PlayerListField extends StatelessWidget {
  const PlayerListField({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.suggestions,
    required this.onReorderItem,
    required this.onSubmitted,
  }) : assert(controllers.length == playerCount),
       assert(focusNodes.length == playerCount);

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final List<String> suggestions;

  /// Same convention as [ReorderableListView.onReorderItem]: `newIndex` is the
  /// final post-removal insertion index (no manual `newIndex -= 1` needed).
  final void Function(int oldIndex, int newIndex) onReorderItem;

  /// Called when the user presses Enter on field [index].
  final void Function(int index) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final trimmedNames = [for (final c in controllers) c.text.trim()];
    final lowerNames = trimmedNames.map((n) => n.toLowerCase()).toList();
    final nonEmptyLower = lowerNames.where((n) => n.isNotEmpty).toList();
    final hasDuplicates = nonEmptyLower.length != nonEmptyLower.toSet().length;

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
          onReorderItem: onReorderItem,
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
/// When [allowRandomDealer] is true, an extra "Willekeurige deler" entry is
/// prepended to the menu.  Picking it reports `null` via [onChanged] (the
/// caller is expected to draw a random dealer later, e.g. on Start).  This
/// replaces an earlier in-field clear (X) affordance — having "random" as a
/// regular menu entry is more discoverable.
class DealerDropdownField extends StatelessWidget {
  const DealerDropdownField({
    super.key,
    required this.controllers,
    required this.value,
    required this.onChanged,
    this.allowRandomDealer = false,
  }) : assert(controllers.length == playerCount);

  final List<TextEditingController> controllers;
  final int? value;

  /// Fires when the user picks a menu entry.  Receives the slot index for a
  /// player pick, or `null` when [allowRandomDealer] is true and the user
  /// picked the "Willekeurige deler" entry.
  final ValueChanged<int?> onChanged;
  final bool allowRandomDealer;

  /// Sentinel menu value for the "random dealer" entry.  Anything outside
  /// `0..playerCount-1` is safe; we use -1 for readability.
  static const int _randomDealerValue = -1;

  @override
  Widget build(BuildContext context) {
    // Material 3 `DropdownMenu` is the modern replacement for the M2-era
    // `DropdownButtonFormField`.  It draws an outlined text-field with a
    // trailing chevron and uses the M3 elevation/shape spec for the
    // dropdown overlay.  `requestFocusOnTap: false` keeps the on-screen
    // keyboard hidden — we want a picker, not text entry.  `expandedInsets`
    // makes the field fill the parent width (the default is intrinsic).
    //
    // No `hintText`: the field always has a selection (a player, or — when
    // [allowRandomDealer] — the random entry as the default), so a placeholder
    // would never show.
    return DropdownMenu<int>(
      key: ValueKey(value),
      initialSelection:
          value ?? (allowRandomDealer ? _randomDealerValue : null),
      enableSearch: false,
      requestFocusOnTap: false,
      expandedInsets: EdgeInsets.zero,
      menuStyle: const MenuStyle(visualDensity: VisualDensity.compact),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onSelected: (v) {
        if (v == null) return;
        if (v == _randomDealerValue) {
          onChanged(null);
          return;
        }
        onChanged(v);
      },
      dropdownMenuEntries: [
        if (allowRandomDealer)
          const DropdownMenuEntry<int>(
            value: _randomDealerValue,
            label: 'Willekeurige deler',
            leadingIcon: Icon(Symbols.shuffle),
          ),
        for (int i = 0; i < playerCount; i++)
          DropdownMenuEntry<int>(
            value: i,
            label: controllers[i].text.trim().isNotEmpty
                ? controllers[i].text
                : 'Speler ${i + 1}',
          ),
      ],
    );
  }
}

/// Shared section strings used by NewGameScreen and EditGameScreen.
/// Centralised here so both screens stay in sync — edit once, applies to both.
const String kPlayersSectionTitle = 'Spelers';
const String kPlayersSectionSubtitle = 'Sleep om de volgorde te wijzigen.';
const String kDealerSectionTitle = 'Deler eerste ronde';
const String kDealerSectionSubtitle =
    'De speler links van de deler kiest het eerste spel.';

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
