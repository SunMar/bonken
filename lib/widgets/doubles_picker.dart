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

  // ---------- Per-pair helpers shared by the bulk actions ----------

  /// True if [selected] has acted on the pair against [target]: either
  /// they are the recorded initiator of a doubled/redoubled pair, or the
  /// pair is `redoubled` (which always implies escalation by [selected]).
  bool _initiatorActed(int selected, int target) {
    final s = widget.doubles.stateFor(selected, target);
    if (s == DoubleState.none) return false;
    return widget.doubles.initiatorFor(selected, target) == selected ||
        s == DoubleState.redoubled;
  }

  /// Apply [selected]'s double against [target] in [matrix]:
  ///   * `none`                            → `doubled` initiator=selected
  ///   * `doubled` (target initiated)       → `redoubled` initiator=target
  ///   * already initiator-acted / redoubled → unchanged
  DoubleMatrix _applyOnePair(DoubleMatrix matrix, int selected, int target) {
    final state = matrix.stateFor(selected, target);
    final initiator = matrix.initiatorFor(selected, target);
    if (state == DoubleState.none) {
      return matrix.withPair(
        selected,
        target,
        DoubleState.doubled,
        initiator: selected,
      );
    }
    if (state == DoubleState.doubled && initiator == target) {
      return matrix.withPair(
        selected,
        target,
        DoubleState.redoubled,
        initiator: target,
      );
    }
    return matrix;
  }

  /// Inverse of [_applyOnePair] used to demote a single chooser pair while
  /// transitioning to Slappe hap. Goal: erase every contribution [selected]
  /// made to the pair, leaving only foreign-initiator action behind.
  ///   * `redoubled`, initiator==selected   → `none` (selected initiated the
  ///     pair; the foreign redouble depends on it, so clear both)
  ///   * `redoubled`, initiator==target     → `doubled` (target's double
  ///     remains; only selected's redouble is removed)
  ///   * `doubled`, initiator==selected     → `none`
  ///   * foreign-initiator `doubled`        → untouched
  DoubleMatrix _demoteOnePair(DoubleMatrix matrix, int selected, int target) {
    final s = matrix.stateFor(selected, target);
    final init = matrix.initiatorFor(selected, target);
    if (s == DoubleState.redoubled && init == target) {
      return matrix.withPair(
        selected,
        target,
        DoubleState.doubled,
        initiator: init,
      );
    }
    if ((s == DoubleState.doubled || s == DoubleState.redoubled) &&
        init == selected) {
      return matrix.withPair(selected, target, DoubleState.none);
    }
    return matrix;
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

  /// Apply a bulk action: the selected initiator declares double against each
  /// player in [targets].  Per-pair behaviour: see [_applyOnePair].
  void _applyBulk(Iterable<int> targets) {
    final selected = _selected;
    if (selected == null) return;
    var matrix = widget.doubles;
    for (final t in targets) {
      if (t == selected) continue;
      matrix = _applyOnePair(matrix, selected, t);
    }
    if (matrix != widget.doubles) widget.onChanged(matrix);
  }

  /// True when, for every target, the selected initiator has acted on the
  /// pair (see [_initiatorActed]). Empty target sets return false.
  bool _isBulkApplied(Iterable<int> targets) {
    final selected = _selected;
    if (selected == null) return false;
    var any = false;
    for (final t in targets) {
      if (t == selected) continue;
      if (!_initiatorActed(selected, t)) return false;
      any = true;
    }
    return any;
  }

  /// True when every target pair is currently `redoubled` and was originally
  /// initiated by the target (the post-state of "Zaal terug"). Used to flag
  /// that bulk button as applied so it can demote everything back to
  /// `doubled` without clearing other-initiator doubles.
  bool _isZaalTerugApplied(Iterable<int> targets) {
    final selected = _selected;
    if (selected == null) return false;
    var any = false;
    for (final t in targets) {
      if (t == selected) continue;
      final s = widget.doubles.stateFor(selected, t);
      if (s != DoubleState.redoubled) return false;
      if (widget.doubles.initiatorFor(selected, t) != t) return false;
      any = true;
    }
    return any;
  }

  /// Clear every pair in [targets] to `none` regardless of state. Used by
  /// the Zaal re-press as an input-correction shortcut: in the Zaal state
  /// every target pair was initiator-acted, so wiping them is safe.
  void _clearBulk(Iterable<int> targets) {
    final selected = _selected;
    if (selected == null) return;
    var matrix = widget.doubles;
    for (final t in targets) {
      if (t == selected) continue;
      if (matrix.stateFor(selected, t) != DoubleState.none) {
        matrix = matrix.withPair(selected, t, DoubleState.none);
      }
    }
    if (matrix != widget.doubles) widget.onChanged(matrix);
  }

  /// Transition to the "Slappe hap" state for the selected initiator: every
  /// non-chooser target gets [_applyOnePair], and the chooser pair is
  /// demoted via [_demoteOnePair]. Single [onChanged] notification.
  void _toSlappeHap(Iterable<int> applyTargets) {
    final selected = _selected;
    if (selected == null) return;
    var matrix = widget.doubles;
    for (final t in applyTargets) {
      if (t == selected) continue;
      matrix = _applyOnePair(matrix, selected, t);
    }
    final chooser = widget.chooserIndex;
    if (chooser != selected) {
      matrix = _demoteOnePair(matrix, selected, chooser);
    }
    if (matrix != widget.doubles) widget.onChanged(matrix);
  }

  /// Inverse of the "Zaal terug" bulk: each `redoubled` pair (which the bulk
  /// escalated from a target-initiated `doubled`) is demoted back to
  /// `doubled`, preserving the target as initiator. The original doubles are
  /// not cleared because they were created by another player, not by bulk.
  void _undoZaalTerug(Iterable<int> targets) {
    final selected = _selected;
    if (selected == null) return;
    var matrix = widget.doubles;
    for (final t in targets) {
      if (t == selected) continue;
      final s = matrix.stateFor(selected, t);
      final init = matrix.initiatorFor(selected, t);
      if (s == DoubleState.redoubled && init == t) {
        matrix = matrix.withPair(
          selected,
          t,
          DoubleState.doubled,
          initiator: t,
        );
      }
    }
    if (matrix != widget.doubles) widget.onChanged(matrix);
  }

  @override
  Widget build(BuildContext context) {
    final order = _doublingOrder;
    final cs = Theme.of(context).colorScheme;

    // The bulk action buttons are enabled when an initiator is selected.
    // For non-chooser initiators both buttons work normally.  The chooser
    // may not initiate doubles, but if multiple other players have doubled
    // (or already redoubled) the chooser, the "Zaal" button switches to a
    // bulk-redouble action against those doublers:
    //   * 2 doublers → "Terug op beide"
    //   * 3 doublers → "Zaal terug"
    // Disabled buttons remain visible so the surrounding layout doesn't
    // shift.
    final selectedIsChooser =
        _selected != null && _selected == widget.chooserIndex;
    final chooserDoublers = !selectedIsChooser
        ? const <int>[]
        : order.where((i) {
            if (i == _selected) return false;
            final s = widget.doubles.stateFor(_selected!, i);
            if (s == DoubleState.none) return false;
            // The pair must have been initiated by the other player; if the
            // chooser somehow initiated, the bulk "terug" doesn't apply.
            return widget.doubles.initiatorFor(_selected!, i) == i;
          }).toList(growable: false);
    final chooserTerugMode =
        selectedIsChooser && chooserDoublers.length >= 2;
    final zaalEnabled = _selected != null &&
        (!selectedIsChooser || chooserTerugMode);
    final zaalLabel = !chooserTerugMode
        ? 'Zaal'
        : (chooserDoublers.length == 3 ? 'Zaal terug' : 'Terug op beide');
    final slappeHapEnabled = _selected != null && !selectedIsChooser;

    final zaalTargets = _selected == null
        ? const <int>[]
        : chooserTerugMode
            ? chooserDoublers
            : order.where((i) => i != _selected).toList(growable: false);
    final slappeHapTargets = _selected == null
        ? const <int>[]
        : order
            .where((i) => i != _selected && i != widget.chooserIndex)
            .toList(growable: false);
    final zaalApplied = zaalEnabled &&
        (chooserTerugMode
            ? _isZaalTerugApplied(zaalTargets)
            : _isBulkApplied(zaalTargets));
    // "Slappe hap" only counts as applied when the non-chooser targets show
    // initiator-action AND the initiator has NOT acted on the chooser pair —
    // otherwise we're in the Zaal state, which owns the filled affordance.
    final slappeHapApplied = slappeHapEnabled &&
        !_initiatorActed(_selected!, widget.chooserIndex) &&
        _isBulkApplied(slappeHapTargets);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Turn order hint
        Text(
          'Volgorde: ${order.map((i) => widget.playerNames[i]).join(' → ')}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

        // --- Bulk action buttons (Zaal / Slappe hap) ---
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(
                child: _BulkButton(
                  label: zaalLabel,
                  filled: zaalApplied,
                  onPressed: !zaalEnabled
                      ? null
                      : zaalApplied
                          ? (chooserTerugMode
                              ? () => _undoZaalTerug(zaalTargets)
                              : () => _clearBulk(zaalTargets))
                          : () => _applyBulk(zaalTargets),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BulkButton(
                  label: 'Slappe hap',
                  filled: slappeHapApplied,
                  onPressed: !slappeHapEnabled
                      ? null
                      : slappeHapApplied
                          ? () => _clearBulk(slappeHapTargets)
                          : () => _toSlappeHap(slappeHapTargets),
                ),
              ),
            ],
          ),
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

class _BulkButton extends StatelessWidget {
  const _BulkButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return filled
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
