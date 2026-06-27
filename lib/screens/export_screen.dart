import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/io_failure.dart';
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
    final packageInfo = await PackageInfo.fromPlatform();
    final bytes = await exportBackup(
      prefs: SharedPreferencesAsync(),
      appVersion: resolveAppVersion(packageInfo),
      includeGames: _scope != _ExportScope.settingsOnly,
      includeSettings: _scope != _ExportScope.gamesOnly,
    );
    final ts = formatFileTimestamp(DateTime.now());
    return (bytes, 'bonken-backup-$ts.zip');
  }

  /// Clears the busy state and reports a failure. Shared by the share/save
  /// catch arms: a benign cancellation never reaches here (it returns normally),
  /// so anything that does is a real failure worth a snackbar.
  void _onFailure(String message) {
    if (!mounted) return;
    setState(() => _busy = null);
    showTimedSnackBar(ScaffoldMessenger.of(context), content: Text(message));
  }

  Future<void> _exportAndShare() async {
    setState(() => _busy = _BusyAction.share);
    try {
      final (bytes, filename) = await _buildExport();
      if (!mounted) return;
      // Returns normally whether the user shared or dismissed the sheet.
      await ref.read(shareFileProvider)(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/zip',
        subject: 'Bonken-backup',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on OutOfSpaceException {
      _onFailure(kOutOfSpaceMessage);
    } on Object {
      _onFailure('Het is mislukt om de gegevens te exporteren.');
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
    } on OutOfSpaceException {
      _onFailure(kOutOfSpaceMessage);
    } on Object {
      _onFailure('Het is mislukt om de gegevens op te slaan.');
    }
  }

  Widget _spinner(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Theme.of(context).colorScheme.onPrimary,
    ),
  );

  /// One export button: disabled while any action is busy, showing a spinner in
  /// place of [icon] when [action] is the running one. Both export buttons share
  /// this busy/spinner wiring.
  Widget _exportButton(
    BuildContext context, {
    required _BusyAction action,
    required Widget icon,
    required String label,
    required Future<void> Function() onPressed,
  }) {
    return FilledButton.icon(
      onPressed: _busy != null ? null : () => unawaited(onPressed()),
      icon: _busy == action ? _spinner(context) : icon,
      label: Text(label),
    );
  }

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
                    title: Text('Alleen spelgeschiedenis'),
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
                _exportButton(
                  context,
                  action: _BusyAction.share,
                  icon: const Icon(Symbols.share),
                  label: 'Export delen',
                  onPressed: _exportAndShare,
                ),
                const SizedBox(height: 8),
              ],
              _exportButton(
                context,
                action: _BusyAction.save,
                icon: const Icon(Symbols.upload),
                label: 'Export opslaan',
                onPressed: _exportAndSave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
