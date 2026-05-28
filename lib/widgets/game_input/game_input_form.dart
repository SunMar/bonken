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
  final GameInput input;

  /// Called with the updated [GameInput] when the user changes a field.
  final void Function(GameInput) onInputChanged;

  @override
  Widget build(BuildContext context) {
    final playerNames = [for (final p in players) p.name];
    return switch (input) {
      final CountsInput ci => _buildCountsForm(ci, playerNames),
      final RecipientInput ri => _buildRecipientForm(ri, playerNames),
    };
  }

  Widget _buildCountsForm(CountsInput ci, List<String> playerNames) {
    final d = game.inputDescriptor as CountsInputDescriptor;
    return CountsStepper(
      playerNames: playerNames,
      counts: [for (final p in players) ci.counts[p.id] ?? 0],
      total: d.total,
      unitLabel: d.unitLabel,
      onCountsChanged: (counts) => onInputChanged(
        CountsInput({
          for (int i = 0; i < players.length; i++) players[i].id: counts[i],
        }),
      ),
    );
  }

  Widget _buildRecipientForm(RecipientInput ri, List<String> playerNames) {
    final d = game.inputDescriptor as RecipientInputDescriptor;

    void updateSlot(int index, String? uuid) {
      final updated = List<String?>.from(ri.recipients);
      updated[index] = uuid;
      onInputChanged(RecipientInput(updated));
    }

    if (d.prompts.length == 1) {
      final uuid = ri.recipients.isNotEmpty ? ri.recipients[0] : null;
      final rawIdx = uuid == null
          ? -1
          : players.indexWhere((p) => p.id == uuid);
      return PlayerPicker(
        playerNames: playerNames,
        selectedIndex: rawIdx < 0 ? null : rawIdx,
        prompt: d.prompts[0],
        onSelected: (i) => updateSlot(0, i == null ? null : players[i].id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < d.prompts.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final uuid = i < ri.recipients.length ? ri.recipients[i] : null;
              final rawIdx = uuid == null
                  ? -1
                  : players.indexWhere((p) => p.id == uuid);
              return PlayerPicker(
                playerNames: playerNames,
                selectedIndex: rawIdx < 0 ? null : rawIdx,
                prompt: d.prompts[i],
                onSelected: (j) =>
                    updateSlot(i, j == null ? null : players[j].id),
              );
            },
          ),
        ],
      ],
    );
  }
}
