import 'package:flutter/material.dart';

import 'player_picker.dart';

/// Two independent [PlayerPicker] widgets stacked vertically.
/// Used for 7e / 13e where the 7th and 13th trick winners are separate inputs.
class DualPlayerPicker extends StatelessWidget {
  const DualPlayerPicker({
    required this.playerNames,
    required this.selectedIndex1,
    required this.prompt1,
    required this.onSelected1,
    required this.selectedIndex2,
    required this.prompt2,
    required this.onSelected2,
    super.key,
  });

  final List<String> playerNames;
  final int? selectedIndex1;
  final String prompt1;
  final ValueChanged<int> onSelected1;
  final int? selectedIndex2;
  final String prompt2;
  final ValueChanged<int> onSelected2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerPicker(
          playerNames: playerNames,
          selectedIndex: selectedIndex1,
          prompt: prompt1,
          onSelected: onSelected1,
        ),
        const SizedBox(height: 16),
        PlayerPicker(
          playerNames: playerNames,
          selectedIndex: selectedIndex2,
          prompt: prompt2,
          onSelected: onSelected2,
        ),
      ],
    );
  }
}
