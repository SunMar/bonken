import 'package:flutter/material.dart';

import '../../models/input_descriptor.dart';
import '../../models/mini_game.dart';
import 'counts_input.dart';
import 'player_picker.dart';

/// Factory widget: renders the correct input form for [game] based on its
/// [InputDescriptor], keeping all game-type knowledge out of the screen layer.
class GameInputForm extends StatelessWidget {
  const GameInputForm({
    required this.game,
    required this.playerNames,
    required this.input,
    required this.onInputChanged,
    super.key,
  });

  final MiniGame game;
  final List<String> playerNames;
  final Map<String, dynamic> input;

  /// Called with the input-map key and new value when the user changes a field.
  final void Function(String key, dynamic value) onInputChanged;

  @override
  Widget build(BuildContext context) {
    return switch (game.inputDescriptor) {
      CountsInputDescriptor d => CountsInput(
        playerNames: playerNames,
        counts: (input[d.inputKey] as List?)?.cast<int>() ?? List.filled(playerCount, 0),
        total: d.total,
        unitLabel: d.unitLabel,
        onCountsChanged: (counts) => onInputChanged(d.inputKey, counts),
      ),
      SinglePlayerInputDescriptor d => PlayerPicker(
        playerNames: playerNames,
        selectedIndex: input[d.inputKey] as int?,
        prompt: d.prompt,
        onSelected: (i) => onInputChanged(d.inputKey, i),
      ),
      DualPlayerInputDescriptor d => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlayerPicker(
            playerNames: playerNames,
            selectedIndex: input[d.inputKey1] as int?,
            prompt: d.prompt1,
            onSelected: (i) => onInputChanged(d.inputKey1, i),
          ),
          const SizedBox(height: 16),
          PlayerPicker(
            playerNames: playerNames,
            selectedIndex: input[d.inputKey2] as int?,
            prompt: d.prompt2,
            onSelected: (i) => onInputChanged(d.inputKey2, i),
          ),
        ],
      ),
    };
  }
}
