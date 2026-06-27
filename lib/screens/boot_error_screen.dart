import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../widgets/app_scaffold.dart';

/// Shown as the initial route when the bootstrap could not determine which
/// screen to start on — specifically when `PackageInfo.fromPlatform()` throws
/// and the legacy-vs-new app id (`isLegacyApp`) can't be resolved (see
/// `main.dart` and ARCHITECTURE.md §8).
///
/// The legacy signal is binary and load-bearing (it routes legacy users to
/// [MigrationScreen]), so a failed read must **not** silently default to either
/// branch — defaulting to "not legacy" would strand a legacy user on the normal
/// app with no path to migrate. Instead we surface this terminal screen: the
/// failure is visible, no routing decision is fabricated, and relaunching (which
/// re-reads the platform metadata) is the recovery.
class BootErrorScreen extends StatelessWidget {
  const BootErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('Bonken')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.error, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Bonken kon niet starten',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Er ging iets mis bij het opstarten. Sluit de app volledig af '
                'en open hem opnieuw. Blijft dit gebeuren, neem dan contact op '
                'via support@suninet.org.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
