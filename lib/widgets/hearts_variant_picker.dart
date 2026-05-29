import 'package:flutter/material.dart';

import '../models/hearts_variant.dart';

/// Full-width [SegmentedButton] for picking a [HeartsVariant].
/// Used in both the new-game screen and the edit-game screen.
class HeartsVariantPicker extends StatelessWidget {
  const HeartsVariantPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final HeartsVariant value;
  final ValueChanged<HeartsVariant> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<HeartsVariant>(
      segments: [
        for (final v in HeartsVariant.values)
          ButtonSegment<HeartsVariant>(value: v, label: Text(v.label)),
      ],
      selected: {value},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }
}
