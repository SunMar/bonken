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

/// Shared subtitle for every settings section: these are app-wide defaults
/// for new games, still adjustable per game.
const String _kDefaultSubtitle =
    'Kies de standaard voor nieuwe spellen. Per spel aanpasbaar.';

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
          FormSectionCard(
            title: kStarterVariantSectionTitle,
            subtitle: _kDefaultSubtitle,
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
            subtitle: _kDefaultSubtitle,
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
