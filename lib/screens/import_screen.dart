import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/export_import_notifier.dart';
import '../state/platform_io_providers.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/form_section_card.dart';
import '../widgets/timed_snackbar.dart';

const _kVersionTooNew = 'Gemaakt met een nieuwere versie van Bonken';
const _kCorrupt = 'Beschadigd of onleesbaar';

/// Builds the user-facing message shown when a partial import occurred — which
/// requested streams were restored and which weren't. [importedGames] /
/// [importedSettings] are what the user asked to import; the [e] flags are what
/// actually committed before the failure.
@visibleForTesting
String partialImportMessage(
  PartialImportException e, {
  required bool importedGames,
  required bool importedSettings,
}) {
  final restored = <String>[];
  final failed = <String>[];
  if (importedGames) {
    (e.gamesImported > 0 ? restored : failed).add('spellen');
  }
  if (importedSettings) {
    (e.settingsUpdated ? restored : failed).add('instellingen');
  }
  return 'Hersteld: ${restored.join(' en ')}. '
      'Niet hersteld: ${failed.join(' en ')}. '
      'Probeer de mislukte gegevens opnieuw te importeren.';
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

sealed class _ImportState {}

final class _Idle extends _ImportState {}

final class _Analyzing extends _ImportState {}

final class _Analyzed extends _ImportState {
  _Analyzed(this.analysis, this.zipBytes);
  final ImportAnalysis analysis;
  final Uint8List zipBytes;
}

final class _Applying extends _ImportState {}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Screen for the import flow.
///
/// Pushed from [SettingsScreen].
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _ImportState _state = _Idle();
  bool _importGames = false;
  bool _importSettings = false;

  Future<void> _pickFile() async {
    Uint8List? bytes;
    try {
      bytes = await ref.read(pickBackupBytesProvider)();
    } on Object {
      return; // User cancelled or permission denied.
    }
    if (bytes == null || !mounted) return;
    // Capture a non-null local: promotion doesn't flow into the setState closure.
    final data = bytes;

    setState(() => _state = _Analyzing());

    try {
      final analysis = await analyzeBackup(data);
      if (!mounted) return;
      setState(() {
        _state = _Analyzed(analysis, data);
        _importGames = analysis.canImportGames;
        _importSettings = analysis.canImportSettings;
      });
    } on BackupTooNew {
      if (!mounted) return;
      setState(() => _state = _Idle());
      _showTooNewError();
    } on Object {
      if (!mounted) return;
      setState(() => _state = _Idle());
      _showError();
    }
  }

  Future<void> _confirmAndApply(_Analyzed current) async {
    final what = switch ((_importGames, _importSettings)) {
      (true, true) => 'spellen en instellingen',
      (true, false) => 'spellen',
      (false, true) => 'instellingen',
      _ => '',
    };
    final confirmed = await showConfirmDialog(
      context,
      title: 'Gegevens vervangen',
      contentText:
          'Je huidige $what worden vervangen door de gegevens uit de backup. '
          'Dit kan niet ongedaan worden gemaakt.',
      confirmLabel: 'Vervangen',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    unawaited(_apply(current));
  }

  Future<void> _apply(_Analyzed current) async {
    final importGames = _importGames;
    setState(() => _state = _Applying());

    try {
      final result = await ref
          .read(importNotifierProvider.notifier)
          .applyImport(
            current.zipBytes,
            importGames: importGames,
            importSettings: _importSettings,
          );
      if (!mounted) return;
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: Text(_successMessage(result, importGames)),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on PartialImportException catch (e) {
      if (!mounted) return;
      // Some data committed before a write failed: storage changed, so pop to
      // the start and tell the user exactly what was and wasn't restored.
      await showInfoDialog(
        context,
        title: 'Import gedeeltelijk gelukt',
        contentText: partialImportMessage(
          e,
          importedGames: importGames,
          importedSettings: _importSettings,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on Object {
      if (!mounted) return;
      setState(() => _state = current);
      _showError();
    }
  }

  void _showError() {
    unawaited(
      showInfoDialog(
        context,
        title: 'Importeren mislukt',
        contentText: '$_kCorrupt. Controleer of het bestand correct is.',
      ),
    );
  }

  void _showTooNewError() {
    unawaited(
      showInfoDialog(
        context,
        title: 'Backup te nieuw',
        contentText: '$_kVersionTooNew. Werk de app bij om hem te importeren.',
      ),
    );
  }

  static String _successMessage(ImportResult result, bool importedGames) {
    final parts = <String>[];
    if (result.settingsUpdated) parts.add('instellingen');
    if (importedGames) {
      parts.add(
        '${result.gamesImported} ${result.gamesImported == 1 ? 'spel' : 'spellen'}',
      );
    }
    return 'De gegevens zijn geïmporteerd (${parts.join(' en ')}).';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Importeer gegevens')),
      body: switch (_state) {
        _Idle() => _buildIdle(),
        _Analyzing() => _buildBusy(),
        _Analyzed() => _buildAnalyzed(_state as _Analyzed),
        _Applying() => _buildBusy(),
      },
    );
  }

  Widget _buildIdle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Symbols.download, size: 48),
            const SizedBox(height: 16),
            Text(
              'Kies een backup-bestand om je speelgeschiedenis en '
              'instellingen te herstellen.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => unawaited(_pickFile()),
              icon: const Icon(Symbols.folder_open),
              label: const Text('Kies bestand'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusy() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildAnalyzed(_Analyzed state) {
    final analysis = state.analysis;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BackupInfoCard(analysis: analysis),
        const SizedBox(height: 12),
        _ImportOptionsCard(
          analysis: analysis,
          importGames: _importGames,
          importSettings: _importSettings,
          onGamesChanged: analysis.canImportGames
              ? (v) => setState(() => _importGames = v ?? false)
              : null,
          onSettingsChanged: analysis.canImportSettings
              ? (v) => setState(() => _importSettings = v ?? false)
              : null,
        ),
        if (_importGames && analysis.gamesCount == 0) ...[
          const SizedBox(height: 8),
          const _ZeroGamesWarning(),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_importGames || _importSettings)
              ? () => unawaited(_confirmAndApply(state))
              : null,
          icon: const Icon(Symbols.download),
          label: const Text('Importeer'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => unawaited(_pickFile()),
          icon: const Icon(Symbols.folder_open),
          label: const Text('Ander bestand kiezen'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _BackupInfoCard extends StatelessWidget {
  const _BackupInfoCard({required this.analysis});

  final ImportAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return FormSectionCard(
      title: 'Backup-details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysis.appVersionThatCreatedIt.isNotEmpty)
            Text(
              'Gemaakt met versie ${analysis.appVersionThatCreatedIt}',
              style: subtitleStyle,
            ),
          Text(
            'Geëxporteerd op ${formatDate(analysis.exportedAt)}',
            style: subtitleStyle,
          ),
        ],
      ),
    );
  }
}

class _ImportOptionsCard extends StatelessWidget {
  const _ImportOptionsCard({
    required this.analysis,
    required this.importGames,
    required this.importSettings,
    required this.onGamesChanged,
    required this.onSettingsChanged,
  });

  final ImportAnalysis analysis;
  final bool importGames;
  final bool importSettings;
  final ValueChanged<bool?>? onGamesChanged;
  final ValueChanged<bool?>? onSettingsChanged;

  static Widget? _streamSubtitle(StreamStatus status) => switch (status) {
    StreamVersionTooNew() => const Text(_kVersionTooNew),
    StreamCorrupt() => const Text(_kCorrupt),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Wat wil je importeren?',
      childPadding: EdgeInsets.zero,
      child: Column(
        children: [
          if (analysis.hasGames)
            CheckboxListTile(
              title: Text('Spellen (${analysis.gamesCount})'),
              subtitle: _streamSubtitle(analysis.gamesStatus),
              value: importGames,
              onChanged: onGamesChanged,
            ),
          if (analysis.hasSettings)
            CheckboxListTile(
              title: const Text('Instellingen'),
              subtitle: _streamSubtitle(analysis.settingsStatus),
              value: importSettings,
              onChanged: onSettingsChanged,
            ),
        ],
      ),
    );
  }
}

class _ZeroGamesWarning extends StatelessWidget {
  const _ZeroGamesWarning();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Symbols.warning, color: cs.onErrorContainer, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'De backup bevat geen spellen. Importeren verwijdert '
                'je huidige spelgeschiedenis.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
