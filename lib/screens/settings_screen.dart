import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../widgets/app_scaffold.dart';

/// Full-screen dialog for configuring app-wide default settings.
/// Pushed with `fullscreenDialog: true`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starterVariant = ref.watch(defaultStarterVariantProvider);
    final heartsVariant = ref.watch(defaultHeartsVariantProvider);
    final theme = Theme.of(context);

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
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text('Uitkomst', style: theme.textTheme.titleSmall),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Standaard voor nieuwe spellen. Per spel aanpasbaar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  RadioGroup<StarterVariant>(
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Extra spelregel harten',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Standaard voor nieuwe spellen. Per spel aanpasbaar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  RadioGroup<HeartsVariant>(
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
