import 'package:flutter/material.dart';

import '../models/double_matrix.dart';
import '../models/mini_game.dart';
import '../utils.dart';

/// Two-panel doubles picker.
///
/// Left panel: 4 players in doubling turn order. Tap to select who is doubling.
/// Right panel: the 3 other players as targets. Tap a target to cycle:
///   none → doubled ("gaat op") → redoubled ("gaat terug") → none.
class DoublesPicker extends StatefulWidget {
  const DoublesPicker({
    required this.playerNames,
    required this.chooserIndex,
    required this.doubles,
    required this.onChanged,
    super.key,
  });

  final List<String> playerNames;

  /// Index of the player who chose this game. The chooser doubles last;
  /// the player to their left goes first.
  final int chooserIndex;

  final DoubleMatrix doubles;
  final ValueChanged<DoubleMatrix> onChanged;

  @override
  State<DoublesPicker> createState() => _DoublesPickerState();
}

class _DoublesPickerState extends State<DoublesPicker> {
  int? _selected; // currently selected initiator index

  List<int> get _doublingOrder {
    final first = (widget.chooserIndex + 1) % 4;
    return List.generate(4, (i) => (first + i) % 4);
  }

  /// Number of other players this player is in any doubled/redoubled situation with.
  int _involvedCount(int player) {
    int count = 0;
    for (int t = 0; t < playerCount; t++) {
      if (t == player) continue;
      if (widget.doubles.stateFor(player, t) != DoubleState.none) count++;
    }
    return count;
  }

  /// Position of [player] in the doubling turn order (0 = first, 3 = last/chooser).
  int _turnIndex(int player) => _doublingOrder.indexOf(player);

  /// True when this player is in at least one redoubled pair.
  bool _hasRedouble(int player) {
    for (int t = 0; t < playerCount; t++) {
      if (t == player) continue;
      if (widget.doubles.stateFor(player, t) == DoubleState.redoubled) {
        return true;
      }
    }
    return false;
  }

  void _cycle(
    int selected,
    int target,
    bool isInitiator, {
    required bool canTargetRedouble,
  }) {
    final current = widget.doubles.stateFor(selected, target);
    final currentInitiator = widget.doubles.initiatorFor(selected, target);

    final DoubleMatrix updated;
    if (isInitiator) {
      // none → doubled → (redoubled if allowed) → none.
      updated = switch (current) {
        DoubleState.none => widget.doubles.withPair(
          selected,
          target,
          DoubleState.doubled,
          initiator: selected,
        ),
        DoubleState.doubled when canTargetRedouble => widget.doubles.withPair(
          selected,
          target,
          DoubleState.redoubled,
          initiator: currentInitiator,
        ),
        DoubleState.doubled || DoubleState.redoubled => widget.doubles.withPair(
          selected,
          target,
          DoubleState.none,
        ),
      };
    } else {
      // Selected player was doubled BY target: only toggle doubled ↔ redoubled.
      updated = switch (current) {
        DoubleState.none => widget.doubles, // shouldn't happen
        DoubleState.doubled => widget.doubles.withPair(
          selected,
          target,
          DoubleState.redoubled,
          initiator: currentInitiator,
        ),
        DoubleState.redoubled => widget.doubles.withPair(
          selected,
          target,
          DoubleState.doubled,
          initiator: currentInitiator,
        ),
      };
    }

    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final order = _doublingOrder;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Turn order hint
        Text(
          'Volgorde: ${order.map((i) => widget.playerNames[i]).join(' → ')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),

        // --- Initiator list ---
        for (final i in order)
          _InitiatorTile(
            name: widget.playerNames[i],
            involvedCount: _involvedCount(i),
            hasRedouble: _hasRedouble(i),
            isSelected: _selected == i,
            isDimmed: _selected != null && _selected != i,
            onTap: () => setState(() {
              _selected = _selected == i ? null : i;
            }),
          ),

        const Divider(height: 24),

        // --- Targets (always rendered with same positional order so rows
        // don't jump when switching initiator; the selected initiator's own
        // row is replaced with an invisible placeholder of the same size).
        // When no initiator is selected, all rows render disabled. ---
        for (final t in order)
          if (_selected != null && t == _selected)
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _TargetTile(
                name: widget.playerNames[t],
                state: DoubleState.none,
                isInitiator: true,
                isInteractive: true,
                onTap: () {},
              ),
            )
          else if (_selected == null)
            _TargetTile(
              name: widget.playerNames[t],
              state: DoubleState.none,
              isInitiator: true,
              isInteractive: false,
              onTap: () {},
            )
          else
            Builder(
              builder: (_) {
                final st = widget.doubles.stateFor(_selected!, t);
                final isInit =
                    st == DoubleState.none ||
                    widget.doubles.initiatorFor(_selected!, t) == _selected;
                // Can only redouble if our turn comes AFTER the initiator's.
                final canRedouble =
                    !isInit && _turnIndex(_selected!) > _turnIndex(t);
                // The chooser is not allowed to initiate doubles — they may
                // only redouble (Terug) someone who doubled them.
                final isChooserInitiating =
                    _selected == widget.chooserIndex && isInit;
                final isInteractive =
                    !isChooserInitiating && (isInit || canRedouble);
                return _TargetTile(
                  name: widget.playerNames[t],
                  state: st,
                  isInitiator: isInit,
                  isInteractive: isInteractive,
                  onTap: () {
                    if (isInteractive) {
                      _cycle(
                        _selected!,
                        t,
                        isInit,
                        canTargetRedouble:
                            _turnIndex(t) > _turnIndex(_selected!),
                      );
                    }
                  },
                );
              },
            ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _InitiatorTile extends StatelessWidget {
  const _InitiatorTile({
    required this.name,
    required this.involvedCount,
    required this.hasRedouble,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
  });

  final String name;
  final int involvedCount;
  final bool hasRedouble;
  final bool isSelected;

  /// True when another initiator is currently selected — this tile renders
  /// as if disabled but remains tappable to switch the selection.
  final bool isDimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final redoubleBg = redoubleContainer(cs, brightness);
    final onRedoubleBg = onRedoubleContainer(cs, brightness);

    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (involvedCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: hasRedouble ? redoubleBg : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$involvedCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: hasRedouble ? onRedoubleBg : cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return isDimmed ? Opacity(opacity: 0.4, child: tile) : tile;
  }
}

// -----------------------------------------------------------------------------

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.name,
    required this.state,
    required this.isInitiator,
    required this.isInteractive,
    required this.onTap,
  });

  final String name;
  final DoubleState state;

  /// True when the currently selected player is the one who initiated the
  /// double on this target (or no double exists yet).  False when the selected
  /// player was doubled BY this target player.
  final bool isInitiator;

  /// False when the selected player was doubled by this target but their own
  /// turn in the declaring order has already passed, so redoubling is not
  /// allowed.
  final bool isInteractive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final redoubleBg = redoubleContainer(cs, brightness);
    final onRedoubleBg = onRedoubleContainer(cs, brightness);

    // Tile background mirrors the pair state regardless of direction.
    final Color? bg = switch (state) {
      DoubleState.none => null,
      DoubleState.doubled => cs.primaryContainer,
      DoubleState.redoubled => redoubleBg,
    };

    Widget chip(String label, Color background, Color foreground) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    // Build the row children depending on direction and state.
    final List<Widget> rowChildren;
    if (isInitiator) {
      rowChildren = [
        if (state == DoubleState.doubled || state == DoubleState.redoubled) ...[
          chip('dubbelt', cs.primaryContainer, cs.onPrimaryContainer),
          const SizedBox(width: 6),
        ],
        Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (state == DoubleState.redoubled) ...[
          const SizedBox(width: 6),
          chip('gaat terug', redoubleBg, onRedoubleBg),
        ],
        const Spacer(),
      ];
    } else {
      // Selected player was doubled BY this target player.
      rowChildren = [
        chip(
          state == DoubleState.redoubled
              ? 'gaat terug op'
              : 'is gedubbeld door',
          state == DoubleState.redoubled ? redoubleBg : cs.primaryContainer,
          state == DoubleState.redoubled ? onRedoubleBg : cs.onPrimaryContainer,
        ),
        const SizedBox(width: 6),
        Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Spacer(),
      ];
    }

    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: isInteractive ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: bg?.withAlpha(80) ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bg ?? cs.outlineVariant),
          ),
          child: Row(children: rowChildren),
        ),
      ),
    );
    return isInteractive ? tile : Opacity(opacity: 0.4, child: tile);
  }
}
