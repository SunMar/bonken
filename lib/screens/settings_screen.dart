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
            subtitle:
                'Kies de standaard voor nieuwe spellen. Per spel aanpasbaar.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            childSpacing: 0,
            child: RadioGroup<StarterVariant>(
              groupValue: starterVariant,
              onChanged: (selected) {
                if (selected == null) return;
                unawaited(
                  ref
                      .read(defaultStarterVariantProvider.notifier)
                      .setVariant(selected),
                );
              },
              child: Column(
                children: [
                  for (final v in StarterVariant.values)
                    RadioListTile<StarterVariant>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v.label),
                      subtitle: Text(v.description),
                      value: v,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FormSectionCard(
            title: kHeartsVariantSectionTitle,
            subtitle:
                'Kies de standaard voor nieuwe spellen. Per spel aanpasbaar.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            childSpacing: 0,
            child: RadioGroup<HeartsVariant>(
              groupValue: heartsVariant,
              onChanged: (selected) {
                if (selected == null) return;
                unawaited(
                  ref
                      .read(defaultHeartsVariantProvider.notifier)
                      .setVariant(selected),
                );
              },
              child: Column(
                children: [
                  for (final v in HeartsVariant.values)
                    RadioListTile<HeartsVariant>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v.label),
                      subtitle: Text(v.description),
                      value: v,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
