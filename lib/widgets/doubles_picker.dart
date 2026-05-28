import 'dart:async';

import 'package:flutter/material.dart';

import '../models/double_matrix.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../theme/app_theme_extensions.dart';
import 'dialogs.dart';
import 'double_state_chip.dart';
import 'selectable_player_tile.dart';

/// Two-panel doubles picker.
///
/// Left panel: 4 players in doubling turn order. Tap to select who is doubling.
/// Right panel: the 3 other players as targets. Tap a target to cycle:
///   none → doubled ("dubbelt") → redoubled ("gaat terug") → none.
class DoublesPicker extends StatefulWidget {
  const DoublesPicker({
    required this.players,
    required this.chooserIndex,
    required this.doubles,
    required this.onChanged,
    super.key,
  });

  final List<Player> players;

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

  // ---------- Shorthand helpers to reduce widget.players[i].id noise ----------

  String _id(int i) => widget.players[i].id;
  DoubleState _stateFor(int a, int b) =>
      widget.doubles.stateFor(_id(a), _id(b));
  String? _initiatorFor(int a, int b) =>
      widget.doubles.initiatorFor(_id(a), _id(b));

  List<int> get _doublingOrder {
    final first = (widget.chooserIndex + 1) % playerCount;
    return List.generate(playerCount, (i) => (first + i) % playerCount);
  }

  /// Number of other players this player is in any doubled/redoubled situation with.
  int _involvedCount(int player) {
    int count = 0;
    for (int t = 0; t < playerCount; t++) {
      if (t == player) continue;
      if (_stateFor(player, t) != DoubleState.none) count++;
    }
    return count;
  }

  /// Position of [player] in the doubling turn order (0 = first, 3 = last/chooser).
  int _turnIndex(int player) => _doublingOrder.indexOf(player);

  /// True when this player is in at least one redoubled pair.
  bool _hasRedouble(int player) {
    for (int t = 0; t < playerCount; t++) {
      if (t == player) continue;
      if (_stateFor(player, t) == DoubleState.redoubled) return true;
    }
    return false;
  }

  // ---------- Per-pair helpers shared by the bulk actions ----------

  /// True if [selected] has acted on the pair against [target]: either
  /// they are the recorded initiator of a doubled/redoubled pair, or the
  /// pair is `redoubled` (which always implies escalation by [selected]).
  bool _initiatorActed(int selected, int target) {
    final s = _stateFor(selected, target);
    if (s == DoubleState.none) return false;
    return _initiatorFor(selected, target) == _id(selected) ||
        s == DoubleState.redoubled;
  }

  /// Apply [selected]'s double against [target] in [matrix]:
  ///   * `none`                            → `doubled` initiator=selected
  ///   * `doubled` (target initiated)       → `redoubled` initiator=target
  ///   * already initiator-acted / redoubled → unchanged
  DoubleMatrix _applyOnePair(DoubleMatrix matrix, int selected, int target) {
    final state = matrix.stateFor(_id(selected), _id(target));
    final initiator = matrix.initiatorFor(_id(selected), _id(target));
    if (state == DoubleState.none) {
      return matrix.withPair(
        _id(selected),
        _id(target),
        DoubleState.doubled,
        initiator: _id(selected),
      );
    }
    if (state == DoubleState.doubled && initiator == _id(target)) {
      return matrix.withPair(
        _id(selected),
        _id(target),
        DoubleState.redoubled,
        initiator: _id(target),
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
    final s = matrix.stateFor(_id(selected), _id(target));
    final init = matrix.initiatorFor(_id(selected), _id(target));
    if (s == DoubleState.redoubled && init == _id(target)) {
      return matrix.withPair(
        _id(selected),
        _id(target),
        DoubleState.doubled,
        initiator: init,
      );
    }
    if ((s == DoubleState.doubled || s == DoubleState.redoubled) &&
        init == _id(selected)) {
      return matrix.withPair(_id(selected), _id(target), DoubleState.none);
    }
    return matrix;
  }

  void _cycle(
    int selected,
    int target,
    bool isInitiator, {
    required bool canTargetRedouble,
  }) {
    final current = _stateFor(selected, target);
    final currentInitiator = _initiatorFor(selected, target);

    final DoubleMatrix updated;
    if (isInitiator) {
      // none → doubled → (redoubled if allowed) → none.
      updated = switch (current) {
        DoubleState.none => widget.doubles.withPair(
          _id(selected),
          _id(target),
          DoubleState.doubled,
          initiator: _id(selected),
        ),
        DoubleState.doubled when canTargetRedouble => widget.doubles.withPair(
          _id(selected),
          _id(target),
          DoubleState.redoubled,
          initiator: currentInitiator,
        ),
        DoubleState.doubled || DoubleState.redoubled => widget.doubles.withPair(
          _id(selected),
          _id(target),
          DoubleState.none,
        ),
      };
    } else {
      // Selected player was doubled BY target: only toggle doubled ↔ redoubled.
      updated = switch (current) {
        DoubleState.none => widget.doubles, // shouldn't happen
        DoubleState.doubled => widget.doubles.withPair(
          _id(selected),
          _id(target),
          DoubleState.redoubled,
          initiator: currentInitiator,
        ),
        DoubleState.redoubled => widget.doubles.withPair(
          _id(selected),
          _id(target),
          DoubleState.doubled,
          initiator: currentInitiator,
        ),
      };
    }

    widget.onChanged(updated);
  }

  // ---------- Forced (rule-overriding) actions ----------
  //
  // The app guides the doubling rules but doesn't hard-enforce them — what
  // happens at the table wins (see ARCHITECTURE.md §2). Two tiles that the
  // rules would block stay visible-but-dimmed and, on tap, offer to force the
  // action through a confirm dialog. Undoing a forced action is a correction,
  // so it toggles back without a prompt.

  /// Tap handler for a redouble whose turn has already passed (the selected
  /// player was doubled by someone later in the order).
  void _handleTurnPassedTap(int selected, int target) {
    // Undoing a forced go-back is a correction — no prompt.
    if (_stateFor(selected, target) == DoubleState.redoubled) {
      _cycle(selected, target, false, canTargetRedouble: false);
      return;
    }
    final actor = widget.players[selected];
    final other = widget.players[target];
    unawaited(
      _confirmForce(
        title: 'Beurt voorbij',
        message:
            'De beurt van ${actor.name} is al voorbij. ${actor.name} kan '
            'daardoor niet meer teruggaan op ${other.name}.',
        confirmLabel: 'Toch teruggaan',
        onConfirm: () =>
            _cycle(selected, target, false, canTargetRedouble: false),
      ),
    );
  }

  /// Tap handler for the chooser initiating a double (normally not allowed —
  /// the chooser may only go back on someone who doubled them).
  void _handleChooserInitiateTap(int selected, int target) {
    // Undoing a forced chooser double is a correction — no prompt. If the
    // target had since redoubled on top, clearing the chooser's double clears
    // the whole pair (the redouble depends on it; mirrors _demoteOnePair).
    if (_stateFor(selected, target) != DoubleState.none) {
      _cycle(selected, target, true, canTargetRedouble: false);
      return;
    }
    final actor = widget.players[selected];
    unawaited(
      _confirmForce(
        title: 'Kiezer mag niet dubbelen',
        message:
            '${actor.name} mag als kiezer niet zelf dubbelen (alleen teruggaan).',
        confirmLabel: 'Toch dubbelen',
        onConfirm: () =>
            _cycle(selected, target, true, canTargetRedouble: false),
      ),
    );
  }

  /// Confirms a rule-overriding action and runs [onConfirm] if the user agrees.
  Future<void> _confirmForce({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showConfirmDialog(
      context,
      title: title,
      contentText: message,
      confirmLabel: confirmLabel,
    );
    if (confirmed == true) onConfirm();
  }

  /// Builds the target tile for [t] given the currently-selected initiator
  /// (`_selected!`). Interactive tiles toggle directly; the two rule-blocked
  /// cases (chooser initiating / redouble after your turn passed) stay dimmed
  /// but tappable and route through a confirm dialog (ARCHITECTURE.md §2).
  Widget _targetTile(int t) {
    final selected = _selected!;
    final st = _stateFor(selected, t);
    final isInit =
        st == DoubleState.none || _initiatorFor(selected, t) == _id(selected);
    // Can only redouble if our turn comes AFTER the initiator's.
    final canRedouble = !isInit && _turnIndex(selected) > _turnIndex(t);
    // The chooser is not allowed to initiate doubles — they may only redouble
    // (Terug) someone who doubled them.
    final isChooserInitiating = selected == widget.chooserIndex && isInit;
    final interactive = !isChooserInitiating && (isInit || canRedouble);

    final VoidCallback onTap;
    if (interactive) {
      onTap = () => _cycle(
        selected,
        t,
        isInit,
        canTargetRedouble: _turnIndex(t) > _turnIndex(selected),
      );
    } else if (isChooserInitiating) {
      onTap = () => _handleChooserInitiateTap(selected, t);
    } else {
      onTap = () => _handleTurnPassedTap(selected, t);
    }

    return _TargetTile(
      name: widget.players[t].name,
      state: st,
      isInitiator: isInit,
      dimmed: !interactive,
      onTap: onTap,
    );
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
      if (_stateFor(selected, t) != DoubleState.redoubled) return false;
      if (_initiatorFor(selected, t) != _id(t)) return false;
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
      if (matrix.stateFor(_id(selected), _id(t)) != DoubleState.none) {
        matrix = matrix.withPair(_id(selected), _id(t), DoubleState.none);
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
      final s = matrix.stateFor(_id(selected), _id(t));
      final init = matrix.initiatorFor(_id(selected), _id(t));
      if (s == DoubleState.redoubled && init == _id(t)) {
        matrix = matrix.withPair(
          _id(selected),
          _id(t),
          DoubleState.doubled,
          initiator: _id(t),
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
        : order
              .where((i) {
                if (i == _selected) return false;
                if (_stateFor(_selected!, i) == DoubleState.none) return false;
                // The pair must have been initiated by the other player; if the
                // chooser somehow initiated, the bulk "terug" doesn't apply.
                return _initiatorFor(_selected!, i) == _id(i);
              })
              .toList(growable: false);
    final chooserTerugMode = selectedIsChooser && chooserDoublers.length >= 2;
    final zaalEnabled =
        _selected != null && (!selectedIsChooser || chooserTerugMode);
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
    final zaalApplied =
        zaalEnabled &&
        (chooserTerugMode
            ? _isZaalTerugApplied(zaalTargets)
            : _isBulkApplied(zaalTargets));
    // "Slappe hap" only counts as applied when the non-chooser targets show
    // initiator-action AND the initiator has NOT acted on the chooser pair —
    // otherwise we're in the Zaal state, which owns the filled affordance.
    final slappeHapApplied =
        slappeHapEnabled &&
        !_initiatorActed(_selected!, widget.chooserIndex) &&
        _isBulkApplied(slappeHapTargets);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Turn order hint
        Text(
          'Volgorde: ${order.map((i) => widget.players[i].name).join(' → ')}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),

        // --- Initiator list ---
        for (final i in order)
          _InitiatorTile(
            name: widget.players[i].name,
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
                name: widget.players[t].name,
                state: DoubleState.none,
                isInitiator: true,
                dimmed: false,
                onTap: null,
              ),
            )
          else if (_selected == null)
            _TargetTile(
              name: widget.players[t].name,
              state: DoubleState.none,
              isInitiator: true,
              dimmed: true,
              onTap: null,
            )
          else
            _targetTile(t),
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
    // Match the 48dp tile rhythm of the initiator/target rows above —
    // the M3 default common-button height is 40dp, which reads short
    // sandwiched between 48dp tile rows.
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
    );
    return filled
        ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
        : OutlinedButton(
            style: style,
            onPressed: onPressed,
            child: Text(label),
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
    final dc = DoubleStateColors.of(context);

    final badge = involvedCount > 0
        ? Badge(
            backgroundColor: hasRedouble
                ? dc.redoubledBackground
                : dc.doubledBackground,
            textColor: hasRedouble
                ? dc.onRedoubledBackground
                : dc.onDoubledBackground,
            label: Text('$involvedCount'),
          )
        : null;

    return SelectablePlayerTile(
      name: name,
      isSelected: isSelected,
      isDimmed: isDimmed,
      onTap: onTap,
      badge: badge,
    );
  }
}

// -----------------------------------------------------------------------------

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.name,
    required this.state,
    required this.isInitiator,
    required this.dimmed,
    required this.onTap,
  });

  final String name;
  final DoubleState state;

  /// True when the currently selected player is the one who initiated the
  /// double on this target (or no double exists yet).  False when the selected
  /// player was doubled BY this target player.
  final bool isInitiator;

  /// Renders the tile at 38% opacity to signal the action is normally not
  /// allowed (turn passed, or chooser initiating). A dimmed tile may still be
  /// tappable when [onTap] is non-null — tapping then offers to force it.
  final bool dimmed;

  /// Tap handler, or null when the tile is inert (placeholder / no initiator
  /// selected).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dc = DoubleStateColors.of(context);

    // Tile background mirrors the pair state regardless of direction.
    final Color? bg = dc.backgroundFor(state);

    Widget chip(String label, Color background, Color foreground) =>
        DoubleStateChip(
          label: label,
          background: background,
          foreground: foreground,
        );

    // Build the row children depending on direction and state.
    final List<Widget> rowChildren;
    if (isInitiator) {
      rowChildren = [
        if (state == DoubleState.doubled || state == DoubleState.redoubled) ...[
          chip('dubbelt', dc.doubledBackground, dc.onDoubledBackground),
          const SizedBox(width: 6),
        ],
        Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (state == DoubleState.redoubled) ...[
          const SizedBox(width: 6),
          chip('gaat terug', dc.redoubledBackground, dc.onRedoubledBackground),
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
          dc.backgroundFor(state)!,
          dc.foregroundFor(state)!,
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // Matches `_InitiatorTile` — see padding comment there.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg?.withValues(alpha: 0.38) ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bg ?? cs.outlineVariant),
          ),
          child: Row(children: rowChildren),
        ),
      ),
    );
    // A dimmed-but-tappable tile is a rule override (turn passed / chooser
    // initiating): announce it as an enabled button with a hint, even though
    // it looks disabled. Truly inert tiles (onTap == null) read as disabled.
    final forceable = dimmed && onTap != null;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        hint: forceable
            ? 'Normaal niet toegestaan; activeer om te forceren'
            : null,
        child: dimmed ? Opacity(opacity: 0.38, child: tile) : tile,
      ),
    );
  }
}
