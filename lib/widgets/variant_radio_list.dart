import 'package:flutter/material.dart';

import '../models/labeled_variant.dart';

/// Vertical [RadioGroup] of [RadioListTile]s — one per [LabeledVariant] value,
/// each showing the value's label as title and description as subtitle.
///
/// Used by [GameRulesSections] (the shared rule sections on settings, new-game
/// and edit-game) and the rules variant dialog in `rules_block_view.dart`, for
/// both [StarterVariant] and [HeartsVariant]. Null selections (a tile tapped
/// while already selected) are ignored.
class VariantRadioList<T extends LabeledVariant> extends StatelessWidget {
  const VariantRadioList({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  /// All selectable values (typically `StarterVariant.values`).
  final List<T> values;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            RadioListTile<T>(
              contentPadding: EdgeInsets.zero,
              title: Text(v.label),
              subtitle: Text(v.description),
              value: v,
            ),
        ],
      ),
    );
  }
}
