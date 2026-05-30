import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/form_section_card.dart';
import '../widgets/variant_radio_list.dart';

/// Full-screen dialog for configuring app-wide default settings.
/// Pushed with `fullscreenDialog: true`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starterVariant = ref.watch(defaultStarterVariantProvider);
    final heartsVariant = ref.watch(defaultHeartsVariantProvider);

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.close),
          tooltip: 'Sluiten',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Instellingen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SettingsNote(),
          const SizedBox(height: 12),
          FormSectionCard(
            title: kStarterVariantSectionTitle,
            subtitle: kStarterVariantSectionSubtitle,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            childSpacing: 0,
            child: VariantRadioList<StarterVariant>(
              values: StarterVariant.values,
              value: starterVariant,
              onChanged: (selected) => unawaited(
                ref
                    .read(defaultStarterVariantProvider.notifier)
                    .setValue(selected),
              ),
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
              onChanged: (selected) => unawaited(
                ref
                    .read(defaultHeartsVariantProvider.notifier)
                    .setValue(selected),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNote extends StatelessWidget {
  const _SettingsNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Symbols.info,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Kies de standaard voor nieuwe spellen. Per spel aanpasbaar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
