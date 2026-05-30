import 'package:flutter/material.dart';

import '../models/labeled_variant.dart';

/// Full-width [SegmentedButton] for picking any [LabeledVariant] value.
///
/// Used by [NewGameScreen], [EditPlayersScreen] and [SettingsScreen] for both
/// [StarterVariant] and [HeartsVariant] — the enums that implement
/// [LabeledVariant].
class VariantPicker<T extends LabeledVariant> extends StatelessWidget {
  const VariantPicker({
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
    return SegmentedButton<T>(
      segments: [
        for (final v in values)
          ButtonSegment<T>(value: v, label: Text(v.label)),
      ],
      selected: {value},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }
}
