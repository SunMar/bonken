import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../navigation/app_routes.dart';
import '../state/game_history_provider.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/timed_snackbar.dart';

const _newAppId = 'org.suninet.bonken';

class MigrationScreen extends ConsumerWidget {
  const MigrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Export reads the raw stored history blob, so only offer it once the
    // history has loaded CLEANLY (hasValue). Gating on a clean load guarantees
    // we never produce a backup from unreadable data: a corrupt history should
    // not occur here (the legacy app reads its own data), and if it somehow did
    // we must not hand the user an export the new app would reject.
    final historyReady = ref.watch(gameHistoryProvider).hasValue;
    return PopScope(
      canPop: false,
      child: AppScaffold(
        appBar: AppBar(
          leading: const AboutIconButton(),
          title: const Text('Bonken'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Symbols.move_to_inbox,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Bonken is verhuisd',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Deze versie van Bonken wordt niet meer bijgewerkt. '
                'Download de nieuwe versie via de Play Store om verder te gaan.\n\n'
                'Je kunt hier eerst je gegevens exporteren en ze daarna importeren in de nieuwe app.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openPlayStore(context),
                icon: const Icon(Symbols.open_in_new),
                label: const Text('Installeer de nieuwe app'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: historyReady ? () => _openExport(context) : null,
                icon: const Icon(Symbols.upload),
                label: const Text('Exporteer gegevens'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPlayStore(BuildContext context) async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_newAppId',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showTimedSnackBar(
          ScaffoldMessenger.of(context),
          content: const Text('Kan de Play Store niet openen.'),
        );
      }
    }
  }

  void _openExport(BuildContext context) {
    unawaited(AppRoutes.openExport(context));
  }
}
