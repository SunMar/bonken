import 'package:flutter/material.dart';

import '../models/labeled_variant.dart';

/// Vertical [RadioGroup] of [RadioListTile]s — one per [LabeledVariant] value,
/// each showing the value's label as title and description as subtitle.
///
/// Used by [GameRulesSections] (the shared rule sections on settings, new-game
/// and edit-game) and the rules variant dialog in `rules_block_view.dart`, for
/// both [StarterVariant] and [HeartsVariant]. Null selections (a tile tapped
/// while already selected) are ignored.
///
/// When [defaultValue] is supplied, the matching tile shows a "standaard" badge
/// next to its label so the user can see which option is their global default.
class VariantRadioList<T extends LabeledVariant> extends StatelessWidget {
  const VariantRadioList({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
    this.defaultValue,
  });

  /// All selectable values (typically `StarterVariant.values`).
  final List<T> values;
  final T value;
  final ValueChanged<T> onChanged;

  /// The global default — its tile receives a "standaard" badge.
  final T? defaultValue;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            RadioListTile<T>(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Text(v.label),
                  if (v == defaultValue) ...[
                    const SizedBox(width: 8),
                    const _DefaultBadge(),
                  ],
                ],
              ),
              subtitle: Text(v.description),
              value: v,
            ),
        ],
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'standaard',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}
