import 'package:flutter/material.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import 'form_section_card.dart';
import 'variant_radio_list.dart';

/// Collapsible "Spelregels" card for [NewGameScreen] and [EditGameScreen].
///
/// Collapsed by default — most users set their preferences once in Settings
/// and never revisit them per-game. Expanded it shows the same StarterVariant
/// and HeartsVariant radio sections as the settings screen.
class GameRulesExpansionCard extends StatelessWidget {
  const GameRulesExpansionCard({
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
    return Card(
      clipBehavior: Clip.hardEdge,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          'Spelregels',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          _VariantSection(
            title: kStarterVariantSectionTitle,
            subtitle: kStarterVariantSectionSubtitle,
            child: VariantRadioList<StarterVariant>(
              values: StarterVariant.values,
              value: starterVariant,
              onChanged: onStarterChanged,
            ),
          ),
          const Divider(height: 24),
          _VariantSection(
            title: kHeartsVariantSectionTitle,
            subtitle: kHeartsVariantSectionSubtitle,
            child: VariantRadioList<HeartsVariant>(
              values: HeartsVariant.values,
              value: heartsVariant,
              onChanged: onHeartsChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantSection extends StatelessWidget {
  const _VariantSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormSectionHeader(title: title, subtitle: subtitle),
        child,
      ],
    );
  }
}
