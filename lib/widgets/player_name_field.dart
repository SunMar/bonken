import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils.dart';

/// Text field for a player's name with autocomplete from previously used names,
/// Tab/Enter handling that advances to the next empty slot, and a max-length
/// formatter.  Shared between the new-game [SetupScreen] and the in-game
/// "edit players" phase of the calculator screen.
class PlayerNameField extends StatelessWidget {
  const PlayerNameField({
    super.key,
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.takenNames,
    required this.onSubmitted,
    required this.isLast,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final Set<String> takenNames;
  final VoidCallback onSubmitted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (textEditingValue) {
        if (suggestions.isEmpty) return const Iterable<String>.empty();
        final query = textEditingValue.text.toLowerCase();
        // Hide suggestions already chosen for other players (case-insensitive).
        final lowerTaken = takenNames.map((n) => n.toLowerCase()).toSet();
        final available = suggestions.where(
          (s) => !lowerTaken.contains(s.toLowerCase()),
        );
        // Show all suggestions (sorted by frequency) when field is empty;
        // otherwise filter to those containing the typed text.
        if (query.isEmpty) return available;
        return available.where((s) => s.toLowerCase().contains(query));
      },
      onSelected: (value) {
        controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        // Re-filter at draw time so the dropdown reflects the latest
        // takenNames even when [optionsBuilder] hasn't been re-run yet
        // (it only runs on text changes, not on parent rebuilds caused by
        // another field being committed).
        final lowerTaken = takenNames.map((n) => n.toLowerCase()).toSet();
        final visible = options
            .where((s) => !lowerTaken.contains(s.toLowerCase()))
            .toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: visible.length,
                itemBuilder: (context, idx) {
                  final option = visible[idx];
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, ctrl, fn, onFieldSubmitted) {
        return Focus(
          // Intercept Tab so it behaves the same as the on-screen "Next"
          // action: commit + advance to the next empty slot (or unfocus).
          // Shift+Tab falls through to the default reverse focus traversal.
          //
          // We deliberately do NOT call RawAutocomplete's [onFieldSubmitted]
          // here: that callback auto-picks the highlighted (first) suggestion
          // as if the user clicked it.  The user must click a suggestion
          // explicitly to accept it.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.tab &&
                !HardwareKeyboard.instance.isShiftPressed) {
              onSubmitted();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: ctrl,
            focusNode: fn,
            decoration: InputDecoration(
              labelText: 'Speler ${index + 1}',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              LengthLimitingTextInputFormatter(kPlayerNameMaxLength),
            ],
            textInputAction: isLast
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: (_) => onSubmitted(),
          ),
        );
      },
    );
  }
}
