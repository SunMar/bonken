import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/game_session.dart';
import '../state/calculator_provider.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/game_history_provider.dart';
import '../state/settings_storage.dart';
import '../state/storage_exceptions.dart';
import '../state/theme_mode_provider.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/game_deleted_snackbar.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/scoreboard_card.dart';
import 'game_screen.dart';
import 'new_game_screen.dart';

/// Home screen: app-bar with About button (leading) and shared
/// Spelregels / Thema actions, past-games list, and "Nieuw spel"
/// button.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    final appBar = AppBar(
      leading: const AboutIconButton(),
      title: const TitleWithRules(title: Text('Bonken')),
      actions: const [SettingsIconButton(), ThemeMenuButton()],
    );

    final settingsError = ref.watch(settingsLoadErrorProvider);
    if (settingsError != null) {
      final (e, st) = settingsError;
      final kind = switch (e) {
        UnsupportedSettingsVersionException() =>
          _StorageErrorKind.unsupportedVersion,
        CorruptSettingsException() => _StorageErrorKind.corrupt,
        _ => _StorageErrorKind.unknown,
      };
      return AppScaffold(
        appBar: appBar,
        body: _StorageErrorScreen(
          title: switch (kind) {
            _StorageErrorKind.unsupportedVersion => 'App bijwerken vereist',
            _StorageErrorKind.corrupt => 'Instellingen beschadigd',
            _StorageErrorKind.unknown => 'Onbekende fout',
          },
          message: switch (kind) {
            _StorageErrorKind.unsupportedVersion =>
              'Je instellingen zijn opgeslagen door een nieuwere versie van '
                  'de app en kunnen niet worden geladen. Update de app of wis de '
                  'instellingen om verder te spelen.',
            _StorageErrorKind.corrupt =>
              'Je instellingen kunnen niet worden gelezen (mogelijk '
                  'beschadigd). Verstuur het foutrapport om dit probleem te melden, '
                  'of wis de instellingen om verder te spelen.',
            _StorageErrorKind.unknown =>
              'Er is een onverwachte fout opgetreden bij het laden van de '
                  'instellingen. Verstuur het foutrapport om dit probleem te '
                  'melden, of wis de instellingen om verder te spelen.',
          },
          showReportButton: kind != _StorageErrorKind.unsupportedVersion,
          exception: e,
          stackTrace: st,
          storageKey: settingsStorageKey,
          clearLabel: 'Instellingen wissen',
          clearConfirmTitle: 'Instellingen wissen',
          clearConfirmText:
              'Je instellingen worden teruggezet naar de standaardwaarden.',
          clearIsDestructive: false,
          onClear: () async {
            await clearSettings();
            ref.invalidate(themeModeProvider);
            ref.invalidate(defaultStarterVariantProvider);
            ref.invalidate(defaultHeartsVariantProvider);
            ref.read(settingsLoadErrorProvider.notifier).clear();
          },
        ),
      );
    }

    final historyAsync = ref.watch(gameHistoryProvider);
    return AppScaffold(
      appBar: appBar,
      body: historyAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) {
          final kind = switch (e) {
            UnsupportedStorageVersionException() =>
              _StorageErrorKind.unsupportedVersion,
            CorruptStorageException() => _StorageErrorKind.corrupt,
            _ => _StorageErrorKind.unknown,
          };
          return _StorageErrorScreen(
            title: switch (kind) {
              _StorageErrorKind.unsupportedVersion => 'App bijwerken vereist',
              _StorageErrorKind.corrupt => 'Geschiedenis beschadigd',
              _StorageErrorKind.unknown => 'Onbekende fout',
            },
            message: switch (kind) {
              _StorageErrorKind.unsupportedVersion =>
                'Je spelgeschiedenis is opgeslagen door een nieuwere versie van '
                    'de app en kan niet worden geladen. Update de app om je '
                    'geschiedenis te bekijken, of wis de geschiedenis om verder te '
                    'spelen.',
              _StorageErrorKind.corrupt =>
                'Je opgeslagen spelgeschiedenis kan niet worden gelezen (mogelijk '
                    'beschadigd). Verstuur het foutrapport om dit probleem te melden, '
                    'of wis de geschiedenis om verder te spelen.',
              _StorageErrorKind.unknown =>
                'Er is een onverwachte fout opgetreden bij het laden van de '
                    'spelgeschiedenis. Verstuur het foutrapport om dit probleem te '
                    'melden, of wis de geschiedenis om verder te spelen.',
            },
            showReportButton: kind != _StorageErrorKind.unsupportedVersion,
            exception: e,
            stackTrace: st,
            storageKey: GameHistoryNotifier.storageKey,
            clearLabel: 'Geschiedenis wissen',
            clearConfirmTitle: 'Geschiedenis wissen',
            clearConfirmText:
                'Alle gespeelde spellen worden permanent verwijderd. '
                'Dit kan niet ongedaan worden gemaakt.',
            clearIsDestructive: true,
            onClear: () =>
                ref.read(gameHistoryProvider.notifier).clearHistory(),
          );
        },
        data: (sessions) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----------------------------------------------------------------
            // History list (or placeholder)
            // ----------------------------------------------------------------
            Expanded(
              child: sessions.isEmpty
                  ? Center(
                      child: Text(
                        'Nog geen gespeelde spellen',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      // +1 for the "Spellen" header at index 0.
                      itemCount: sessions.length + 1,
                      // separator-i sits between item-i and item-(i+1):
                      // index 0 = below the header (smaller gap), the rest
                      // = between cards.
                      separatorBuilder: (_, index) =>
                          SizedBox(height: index == 0 ? 8 : 10),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Spellen',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      letterSpacing: 0.5,
                                    ),
                              ),
                            ),
                          );
                        }
                        final session = sessions[index - 1];
                        return _GameSessionCard(
                          session: session,
                          onDelete: () async {
                            // Capture the messenger BEFORE any awaits, so we
                            // don't depend on a context that may change.
                            final messenger = ScaffoldMessenger.of(context);
                            final container = ProviderScope.containerOf(
                              context,
                              listen: false,
                            );
                            await ref
                                .read(gameHistoryProvider.notifier)
                                .deleteGame(session.id);
                            showGameDeletedSnackBar(
                              messenger,
                              container,
                              session,
                            );
                          },
                        );
                      },
                    ),
            ),

            // ----------------------------------------------------------------
            // New-game button (always pinned at bottom)
            // ----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: PrimaryActionButton(
                icon: const Icon(Symbols.add),
                label: const Text('Nieuw spel'),
                onPressed: () {
                  // NewGameScreen holds its own local working state; the
                  // calculator provider is only mutated when the user
                  // confirms "Start spel".
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NewGameScreen(),
                        fullscreenDialog: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Storage-error screen — shared by game-history and settings error cases.
// All variable content (text, actions, storage key) is supplied by the caller.
// =============================================================================

enum _StorageErrorKind { unsupportedVersion, corrupt, unknown }

class _StorageErrorScreen extends StatelessWidget {
  const _StorageErrorScreen({
    required this.title,
    required this.message,
    required this.showReportButton,
    required this.exception,
    required this.stackTrace,
    required this.storageKey,
    required this.clearLabel,
    required this.clearConfirmTitle,
    required this.clearConfirmText,
    required this.clearIsDestructive,
    required this.onClear,
  });

  final String title;
  final String message;
  final bool showReportButton;
  final Object? exception;
  final StackTrace? stackTrace;

  /// SharedPreferences key whose raw value is included in the debug report.
  final String storageKey;

  final String clearLabel;
  final String clearConfirmTitle;
  final String clearConfirmText;
  final bool clearIsDestructive;

  /// Called (after confirmation) when the user taps the clear button.
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.error, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (showReportButton) ...[
              FilledButton.tonal(
                onPressed: () => unawaited(
                  _sendErrorReport(context, exception, stackTrace, storageKey),
                ),
                child: const Text('Verstuur foutrapport'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.tonal(
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: clearConfirmTitle,
                  contentText: clearConfirmText,
                  confirmLabel: 'Wissen',
                  destructive: clearIsDestructive,
                );
                if (confirmed != true) return;
                await onClear();
              },
              child: Text(clearLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Error report helpers
// =============================================================================

/// Support address the error report is mailed to (and shown as a fallback when
/// no mail app is available). Defined once so the two references can't drift.
const String _supportEmail = 'support@suninet.org';

/// Upper bounds on the variable-length parts of the debug report. The whole
/// report is URL-encoded into a `mailto:` body, and many mail clients/OSes
/// silently truncate long `mailto:` URLs — so cap the parts that can grow
/// unbounded (the raw storage blob and the stack trace) to keep the report
/// intact. The head of each is the most useful for diagnosis.
const int _maxRawDataChars = 3000;
const int _maxStackTraceChars = 1500;

Future<void> _sendErrorReport(
  BuildContext context,
  Object? exception,
  StackTrace? stackTrace,
  String storageKey,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Verstuur foutrapport',
    contentText:
        'Het rapport bevat de opgeslagen gegevens, inclusief '
        'spelersnamen. Er worden geen andere gegevens meegestuurd.',
    confirmLabel: 'Versturen',
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  final prefs = await SharedPreferences.getInstance();
  final rawData = prefs.getString(storageKey);

  final report = buildDebugReport(
    exception,
    stackTrace,
    rawData,
    DateTime.now().toUtc(),
  );
  final emailBody = _buildEmailBody(report);

  final uri = Uri.parse(
    'mailto:$_supportEmail'
    '?subject=${Uri.encodeComponent('Bonken foutrapport')}'
    '&body=${Uri.encodeComponent(emailBody)}',
  );

  final launched = await launchUrl(uri);
  if (!launched && context.mounted) {
    await showInfoDialog(
      context,
      title: 'Kan e-mail niet openen',
      contentText:
          'Er is geen e-mailapp beschikbaar op dit apparaat. '
          'Neem contact op via $_supportEmail.',
    );
  }
}

/// Builds the plain-text debug report mailed in the error report. The
/// variable-length parts (stack trace, raw storage blob) are capped via
/// [_truncate] so the `mailto:` body stays within client/OS URL limits.
///
/// Exposed for tests so the truncation can be verified without launching mail.
@visibleForTesting
String buildDebugReport(
  Object? exception,
  StackTrace? stackTrace,
  String? rawData,
  DateTime now,
) {
  final buf = StringBuffer()..writeln('Date: ${now.toIso8601String()}');
  if (exception != null) {
    buf
      ..writeln()
      ..writeln('=== Exception ===')
      ..writeln('${exception.runtimeType}: $exception');
  }
  if (exception is HasCause) {
    buf
      ..writeln()
      ..writeln('=== Cause ===')
      ..writeln('${exception.cause.runtimeType}: ${exception.cause}');
  }
  if (stackTrace != null) {
    buf
      ..writeln()
      ..writeln('=== Stack trace ===')
      ..writeln(_truncate(stackTrace.toString(), _maxStackTraceChars));
  }
  if (rawData != null) {
    buf
      ..writeln()
      ..writeln('=== Raw storage data ===')
      ..writeln(_truncate(rawData, _maxRawDataChars));
  }
  return buf.toString();
}

/// Caps [text] at [maxChars], appending a marker noting how many characters
/// were dropped. Keeps the `mailto:` body small enough that mail clients don't
/// silently truncate the report mid-URL.
String _truncate(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  final dropped = text.length - maxChars;
  return '${text.substring(0, maxChars)}\n…[ingekort: $dropped tekens]';
}

String _buildEmailBody(String debugReport) {
  return 'Voeg hier uw bericht toe (optioneel)...'
      '\n\n\n'
      '────────────────────────────────────────────────────\n'
      'Bonken foutrapport — automatisch gegenereerd\n'
      '────────────────────────────────────────────────────\n'
      '\n'
      '$debugReport';
}

// =============================================================================
// Past-game card
// =============================================================================

class _GameSessionCard extends ConsumerWidget {
  const _GameSessionCard({required this.session, required this.onDelete});

  final GameSession session;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    void onTap() {
      ref.read(calculatorProvider.notifier).loadSession(session);
      unawaited(
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const GameScreen())),
      );
    }

    // Muted tint for the trailing Verwijderen IconButton (standard 48dp
    // tap target). Any future trailing icon inherits the same tint.
    final mutedIconTheme = mutedIconButtonTheme(
      theme,
      foregroundColor: cs.onSurfaceVariant,
    );

    final names = session.displayedPlayerNames.join(', ');
    final date = formatDate(session.scoredAt);
    // Announce the custom game name (when set) so screen-reader users get the
    // same recognition cue sighted users see on the card.
    final namePart = session.gameName != null ? '"${session.gameName}" ' : '';
    final tapLabel = session.isFinished
        ? 'Afgerond spel ${namePart}met $names — $date'
        : 'Lopend spel ${namePart}met $names — ronde ${session.rounds.length + 1} '
              'van ${GameSession.totalRounds} — $date';

    return Theme(
      data: mutedIconTheme,
      child: ScoreboardCard(
        tapSemanticLabel: tapLabel,
        // Zero outer margin so the ListView's separator owns all
        // vertical spacing between cards (avoids the default Card
        // margin compounding with the separator gap).
        margin: EdgeInsets.zero,
        roundsPlayed: session.rounds.length,
        playerNames: session.displayedPlayerNames,
        scores: session.displayedScores,
        winners: session.isFinished ? session.displayedWinnerIndices : const [],
        onTap: onTap,
        scoredAt: session.scoredAt,
        gameName: session.gameName,
        headerTrailing: IconButton(
          icon: const Icon(Symbols.delete),
          tooltip: 'Verwijderen',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
