import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../navigation/app_routes.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/settings_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/form_section_card.dart';
import '../widgets/game_rules_card.dart';
import '../widgets/info_banner.dart';

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
              ref.read(settingsProvider.notifier).setDefaultStarterVariant(v),
            ),
            onHeartsChanged: (v) => unawaited(
              ref.read(settingsProvider.notifier).setDefaultHeartsVariant(v),
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
          _DataTile(
            icon: Symbols.upload,
            title: 'Exporteer gegevens',
            subtitle: 'Maak een backupbestand',
            onTap: () => unawaited(AppRoutes.openExport(context)),
          ),
          _DataTile(
            icon: Symbols.download,
            title: 'Importeer gegevens',
            subtitle: 'Herstel vanuit een backupbestand',
            onTap: () => unawaited(AppRoutes.openImport(context)),
          ),
        ],
      ),
    );
  }
}

/// A single tappable data-management row (Export / Import). Carries the
/// hand-written `MergeSemantics`/`Semantics(button)` wrapper required for a
/// custom tile (§2) in one place, so both rows share it identically.
class _DataTile extends StatelessWidget {
  const _DataTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: ListTile(
          leading: Icon(icon),
          minVerticalPadding: 14,
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: onTap,
        ),
      ),
    );
  }
}
