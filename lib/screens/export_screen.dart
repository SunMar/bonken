import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/share_service.dart' show kShareUnsupportedMessage;
import '../state/export_import_notifier.dart';
import '../state/platform_io_providers.dart';
import '../utils.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/form_section_card.dart';
import '../widgets/timed_snackbar.dart';

enum _ExportScope { all, gamesOnly, settingsOnly }

enum _BusyAction { share, save }

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
  _BusyAction? _busy;

  Future<(Uint8List, String)> _buildExport() async {
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
    final ts = formatFileTimestamp(DateTime.now());
    return (bytes, 'bonken-backup-$ts.zip');
  }

  Future<void> _exportAndShare() async {
    setState(() => _busy = _BusyAction.share);
    try {
      final (bytes, filename) = await _buildExport();
      if (!mounted) return;
      final shared = await ref.read(shareFileProvider)(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/zip',
        subject: 'Bonken-backup',
      );
      if (!mounted) return;
      if (!shared) {
        setState(() => _busy = null);
        showTimedSnackBar(
          ScaffoldMessenger.of(context),
          content: const Text(kShareUnsupportedMessage),
        );
        return;
      }
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _busy = null);
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: const Text('Het is mislukt om de gegevens te exporteren.'),
      );
    }
  }

  Future<void> _exportAndSave() async {
    setState(() => _busy = _BusyAction.save);
    try {
      final (bytes, filename) = await _buildExport();
      if (!mounted) return;
      final saved = await ref.read(saveZipFileProvider)(
        bytes: bytes,
        filename: filename,
      );
      if (!mounted) return;
      if (!saved) {
        // User cancelled the SAF picker (Android).
        setState(() => _busy = null);
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        showTimedSnackBar(
          messenger,
          content: const Text('Export opgeslagen in Bestanden → Bonken'),
        );
      }
    } on Object {
      if (!mounted) return;
      setState(() => _busy = null);
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: const Text('Het is mislukt om de gegevens op te slaan.'),
      );
    }
  }

  Widget _spinner(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Theme.of(context).colorScheme.onPrimary,
    ),
  );

  @override
  Widget build(BuildContext context) {
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
                if (_busy == null && v != null) setState(() => _scope = v);
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!kIsWeb) ...[
                FilledButton.icon(
                  onPressed: _busy != null
                      ? null
                      : () => unawaited(_exportAndShare()),
                  icon: _busy == _BusyAction.share
                      ? _spinner(context)
                      : const Icon(Symbols.share),
                  label: const Text('Export delen'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _busy != null
                    ? null
                    : () => unawaited(_exportAndSave()),
                icon: _busy == _BusyAction.save
                    ? _spinner(context)
                    : const Icon(Symbols.upload),
                label: const Text('Export opslaan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
