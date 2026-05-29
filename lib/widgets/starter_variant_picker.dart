import 'package:flutter/material.dart';

import '../models/starter_variant.dart';

/// Full-width [SegmentedButton] for picking a [StarterVariant].
/// Used in both the new-game screen and the edit-game screen.
class StarterVariantPicker extends StatelessWidget {
  const StarterVariantPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final StarterVariant value;
  final ValueChanged<StarterVariant> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StarterVariant>(
      segments: [
        for (final v in StarterVariant.values)
          ButtonSegment<StarterVariant>(value: v, label: Text(v.label)),
      ],
      selected: {value},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }
}
