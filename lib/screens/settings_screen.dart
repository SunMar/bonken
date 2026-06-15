import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/form_section_card.dart';
import '../widgets/game_rules_card.dart';
import '../widgets/info_banner.dart';
import 'export_screen.dart';
import 'import_screen.dart';

/// Screen for configuring app-wide default settings.
///
/// Pushed from [HomeScreen] via [SettingsIconButton].
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starterVariant = ref.watch(defaultStarterVariantProvider);
    final heartsVariant = ref.watch(defaultHeartsVariantProvider);

    return AppScaffold(
      appBar: AppBar(title: const Text('Instellingen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SettingsNote(),
          const SizedBox(height: 12),
          GameRulesSections(
            starterVariant: starterVariant,
            heartsVariant: heartsVariant,
            onStarterChanged: (v) => unawaited(
              ref.read(defaultStarterVariantProvider.notifier).setValue(v),
            ),
            onHeartsChanged: (v) => unawaited(
              ref.read(defaultHeartsVariantProvider.notifier).setValue(v),
            ),
            showDefaultBadge: false,
          ),
          const SizedBox(height: 12),
          const _DataSection(),
        ],
      ),
    );
  }
}

class _SettingsNote extends StatelessWidget {
  const _SettingsNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InfoBanner(
      child: Text(
        'Kies de standaard voor nieuwe spellen. Per spel aanpasbaar.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: cs.onSecondaryContainer),
      ),
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Gegevens',
      childPadding: EdgeInsets.zero,
      child: Column(
        children: [
          MergeSemantics(
            child: Semantics(
              button: true,
              child: ListTile(
                leading: const Icon(Symbols.upload),
                minVerticalPadding: 14,
                title: const Text('Exporteer gegevens'),
                subtitle: const Text('Maak een backupbestand'),
                onTap: () => unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExportScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          MergeSemantics(
            child: Semantics(
              button: true,
              child: ListTile(
                leading: const Icon(Symbols.download),
                minVerticalPadding: 14,
                title: const Text('Importeer gegevens'),
                subtitle: const Text('Herstel vanuit een backupbestand'),
                onTap: () => unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ImportScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
