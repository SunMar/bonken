import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/share_service.dart' show kShareUnsupportedMessage;
import '../state/export_import_notifier.dart';
import '../state/platform_io_providers.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/form_section_card.dart';
import '../widgets/timed_snackbar.dart';

enum _ExportScope { all, gamesOnly, settingsOnly }

/// Screen for choosing export scope and triggering the backup export.
///
/// Pushed from [SettingsScreen].
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  _ExportScope _scope = _ExportScope.all;
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final (prefs, packageInfo) = await (
        SharedPreferences.getInstance(),
        PackageInfo.fromPlatform(),
      ).wait;
      final bytes = await exportBackup(
        prefs: prefs,
        appVersion: resolveAppVersion(packageInfo),
        includeGames: _scope != _ExportScope.settingsOnly,
        includeSettings: _scope != _ExportScope.gamesOnly,
      );
      if (!mounted) return;
      final now = DateTime.now();
      final ts =
          '${now.year.toString().padLeft(4, '0')}'
          '-${now.month.toString().padLeft(2, '0')}'
          '-${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}'
          '-${now.minute.toString().padLeft(2, '0')}';
      final shared = await ref.read(shareFileProvider)(
        bytes: bytes,
        filename: 'bonken-backup-$ts.zip',
        mimeType: 'application/zip',
        subject: 'Bonken-backup',
      );
      if (!mounted) return;
      if (!shared) {
        // Platform refused the share sheet (e.g. Web Share API unavailable).
        // Keep the screen open so the user can retry rather than silently
        // popping as if the export succeeded.
        setState(() => _busy = false);
        showTimedSnackBar(
          ScaffoldMessenger.of(context),
          content: const Text(kShareUnsupportedMessage),
        );
        return;
      }
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: const Text('Exporteren mislukt. Probeer opnieuw.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('Exporteer gegevens')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormSectionCard(
            title: 'Wat wil je exporteren?',
            childPadding: EdgeInsets.zero,
            child: RadioGroup<_ExportScope>(
              groupValue: _scope,
              onChanged: (v) {
                if (!_busy && v != null) setState(() => _scope = v);
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<_ExportScope>(
                    title: Text('Alles'),
                    subtitle: Text('Speelgeschiedenis en instellingen'),
                    minVerticalPadding: 14,
                    value: _ExportScope.all,
                  ),
                  RadioListTile<_ExportScope>(
                    title: Text('Alleen speelgeschiedenis'),
                    value: _ExportScope.gamesOnly,
                  ),
                  RadioListTile<_ExportScope>(
                    title: Text('Alleen instellingen'),
                    value: _ExportScope.settingsOnly,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => unawaited(_export()),
            icon: _busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Symbols.upload),
            label: const Text('Exporteer'),
          ),
        ],
      ),
    );
  }
}
