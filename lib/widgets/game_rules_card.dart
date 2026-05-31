import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import 'form_section_card.dart';
import 'variant_radio_list.dart';

/// Tappable "Spelregels" card for [NewGameScreen] and [EditGameScreen].
///
/// Summarises how the per-game rules deviate from the player's configured
/// defaults ([defaultStarterVariantProvider] / [defaultHeartsVariantProvider]):
/// one row per differing rule, or a reassuring note when nothing deviates.
/// There is no canonical rule set, so "default" always means the player's own
/// configured choice — never an imposed standard.
///
/// Tapping opens a modal bottom sheet with the same [FormSectionCard] layout
/// used by [SettingsScreen]. Selections update the caller's local state
/// immediately via the callbacks; nothing is persisted until the screen's own
/// commit action (Start spel / Opslaan).
class GameRulesCard extends ConsumerWidget {
  const GameRulesCard({
    super.key,
    required this.starterVariant,
    required this.heartsVariant,
    required this.onStarterChanged,
    required this.onHeartsChanged,
  });

  final StarterVariant starterVariant;
  final HeartsVariant heartsVariant;
  final ValueChanged<StarterVariant> onStarterChanged;
  final ValueChanged<HeartsVariant> onHeartsChanged;

  void _openSheet(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => _GameRulesSheet(
          starterVariant: starterVariant,
          heartsVariant: heartsVariant,
          onStarterChanged: onStarterChanged,
          onHeartsChanged: onHeartsChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final defaultStarter = ref.watch(defaultStarterVariantProvider);
    final defaultHearts = ref.watch(defaultHeartsVariantProvider);

    // One row per rule that differs from the player's configured default.
    final deviations = <Widget>[
      if (starterVariant != defaultStarter)
        Text(
          '$kStarterVariantSectionTitle → ${starterVariant.label}',
          style: subtitleStyle,
        ),
      if (heartsVariant != defaultHearts)
        Text(
          '$kHeartsVariantSectionTitle → ${heartsVariant.label}',
          style: subtitleStyle,
        ),
    ];

    // A custom InkWell tile (not ListTile) so the variable-height summary lays
    // out cleanly; the explicit MergeSemantics + Semantics(button) makes the
    // whole card read as one labelled button (per the a11y convention).
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Card(
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: () => _openSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Spelregels', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        if (deviations.isEmpty)
                          Text(
                            'Je speelt met je standaardregels.',
                            style: subtitleStyle,
                          )
                        else
                          ...deviations,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Symbols.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two [FormSectionCard] rule sections shared by [_GameRulesSheet] and
/// [SettingsScreen]. Callers supply current values and callbacks; state is
/// managed by the caller.
class GameRulesSections extends StatelessWidget {
  const GameRulesSections({
    super.key,
    required this.starterVariant,
    required this.heartsVariant,
    required this.onStarterChanged,
    required this.onHeartsChanged,
  });

  final StarterVariant starterVariant;
  final HeartsVariant heartsVariant;
  final ValueChanged<StarterVariant> onStarterChanged;
  final ValueChanged<HeartsVariant> onHeartsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FormSectionCard(
          title: kStarterVariantSectionTitle,
          subtitle: kStarterVariantSectionSubtitle,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          childSpacing: 0,
          child: VariantRadioList<StarterVariant>(
            values: StarterVariant.values,
            value: starterVariant,
            onChanged: onStarterChanged,
          ),
        ),
        const SizedBox(height: 12),
        FormSectionCard(
          title: kHeartsVariantSectionTitle,
          subtitle: kHeartsVariantSectionSubtitle,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          childSpacing: 0,
          child: VariantRadioList<HeartsVariant>(
            values: HeartsVariant.values,
            value: heartsVariant,
            onChanged: onHeartsChanged,
          ),
        ),
      ],
    );
  }
}

class _GameRulesSheet extends StatefulWidget {
  const _GameRulesSheet({
    required this.starterVariant,
    required this.heartsVariant,
    required this.onStarterChanged,
    required this.onHeartsChanged,
  });

  final StarterVariant starterVariant;
  final HeartsVariant heartsVariant;
  final ValueChanged<StarterVariant> onStarterChanged;
  final ValueChanged<HeartsVariant> onHeartsChanged;

  @override
  State<_GameRulesSheet> createState() => _GameRulesSheetState();
}

class _GameRulesSheetState extends State<_GameRulesSheet> {
  late StarterVariant _starterVariant;
  late HeartsVariant _heartsVariant;

  @override
  void initState() {
    super.initState();
    _starterVariant = widget.starterVariant;
    _heartsVariant = widget.heartsVariant;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Spelregels',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Symbols.close),
                tooltip: 'Sluiten',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: GameRulesSections(
              starterVariant: _starterVariant,
              heartsVariant: _heartsVariant,
              onStarterChanged: (v) {
                setState(() => _starterVariant = v);
                widget.onStarterChanged(v);
              },
              onHeartsChanged: (v) {
                setState(() => _heartsVariant = v);
                widget.onHeartsChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
