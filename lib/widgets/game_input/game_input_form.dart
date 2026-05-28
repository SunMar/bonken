import 'package:flutter/material.dart';

import '../../models/input_descriptor.dart';
import '../../models/mini_game.dart';
import '../../models/player.dart';
import 'counts_input.dart';
import 'player_picker.dart';

/// Factory widget: renders the correct input form for [game] based on its
/// [InputDescriptor], keeping all game-type knowledge out of the screen layer.
class GameInputForm extends StatelessWidget {
  const GameInputForm({
    required this.game,
    required this.players,
    required this.input,
    required this.onInputChanged,
    super.key,
  });

  final MiniGame game;
  final List<Player> players;
  final Map<String, dynamic> input;

  /// Called with the input-map key and new value when the user changes a field.
  final void Function(String key, dynamic value) onInputChanged;

  @override
  Widget build(BuildContext context) {
    final playerNames = [for (final p in players) p.name];
    return switch (game.inputDescriptor) {
      final CountsInputDescriptor d => CountsInput(
        playerNames: playerNames,
        counts: [
          for (final p in players)
            (input[d.inputKey] as Map<String, dynamic>?)?[p.id] as int? ?? 0,
        ],
        total: d.total,
        unitLabel: d.unitLabel,
        onCountsChanged: (counts) => onInputChanged(d.inputKey, {
          for (int i = 0; i < players.length; i++) players[i].id: counts[i],
        }),
      ),
      final SinglePlayerInputDescriptor d => _pickerFor(
        inputKey: d.inputKey,
        prompt: d.prompt,
        playerNames: playerNames,
      ),
      final DualPlayerInputDescriptor d => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pickerFor(
            inputKey: d.inputKey1,
            prompt: d.prompt1,
            playerNames: playerNames,
          ),
          const SizedBox(height: 16),
          _pickerFor(
            inputKey: d.inputKey2,
            prompt: d.prompt2,
            playerNames: playerNames,
          ),
        ],
      ),
    };
  }

  Widget _pickerFor({
    required String inputKey,
    required String prompt,
    required List<String> playerNames,
  }) {
    final uuid = input[inputKey] as String?;
    final rawIdx = uuid == null ? -1 : players.indexWhere((p) => p.id == uuid);
    return PlayerPicker(
      playerNames: playerNames,
      selectedIndex: rawIdx < 0 ? null : rawIdx,
      prompt: prompt,
      onSelected: (i) =>
          onInputChanged(inputKey, i == null ? null : players[i].id),
    );
  }
}
