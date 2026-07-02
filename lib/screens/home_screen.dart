import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/game_session.dart';
import '../navigation/app_routes.dart';
import '../screens/qr_scanner_screen.dart' show kScanQrTitle;
import '../state/calculator_keep_alive.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../state/highlight_game_provider.dart';
import '../state/settings_provider.dart';
import '../state/settings_storage.dart';
import '../state/storage_exceptions.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/full_width_bottom_bar_button.dart';
import '../widgets/game_deleted_snackbar.dart';
import '../widgets/scoreboard_card.dart';

/// Home screen: app-bar with About button (leading) and shared
/// Spelregels / Thema actions, past-games list, and "Nieuw spel"
/// button.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appBar = AppBar(
      leading: const AboutIconButton(),
      title: const TitleWithRules(title: Text('Bonken')),
      actions: const [SettingsIconButton(), ThemeMenuButton()],
    );

    // Settings failed to load → full-screen error. Strip the app-bar actions
    // (theme menu + settings) down to a bare bar like MigrationScreen: those
    // write through the very settings blob that's unreadable, so a write would
    // decode the corrupt/unsupported data and throw — and being unawaited, fail
    // silently while the corruption persists. "Instellingen wissen" is the one
    // repair, so steer the user there.
    final settingsError = ref.watch(settingsLoadErrorProvider);
    if (settingsError != null) {
      final (e, st) = settingsError;
      return _HomeErrorView(
        appBar: AppBar(
          leading: const AboutIconButton(),
          title: const Text('Bonken'),
        ),
        exception: e,
        stackTrace: st,
        descriptor: _settingsErrorDescriptor(ref),
      );
    }

    final historyAsync = ref.watch(gameHistoryProvider);
    // Game history failed to load → full-screen error. The app bar keeps its
    // actions here: settings loaded fine, so the theme menu and settings screen
    // still work.
    if (historyAsync.hasError) {
      return _HomeErrorView(
        appBar: appBar,
        exception: historyAsync.error!,
        stackTrace: historyAsync.stackTrace,
        descriptor: _historyErrorDescriptor(ref),
      );
    }

    return AppScaffold(
      appBar: appBar,
      bottomBar: historyAsync.hasValue
          ? FullWidthBottomBarButton(
              leading: IconButton(
                icon: const Icon(Symbols.qr_code_scanner),
                tooltip: kScanQrTitle,
                onPressed: () => unawaited(AppRoutes.openScanQr(context)),
              ),
              icon: const Icon(Symbols.add),
              label: const Text('Nieuw spel'),
              onPressed: () {
                // NewGameScreen holds its own local working state; the
                // calculator provider is only mutated when the user
                // confirms "Start spel".
                unawaited(AppRoutes.openNewGame(context));
              },
            )
          : null,
      // History is either still loading or loaded — the error case returned
      // above. hasValue covers skipLoadingOnReload: a reload keeps the existing
      // list rather than flashing the spinner.
      body: historyAsync.hasValue
          ? _sessionsBody(context, historyAsync.requireValue)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _sessionsBody(BuildContext context, List<GameSession> sessions) {
    if (sessions.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Text(
          'Nog geen gespeelde spellen',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return _SessionsList(sessions: sessions);
  }
}

/// The past-games list. Stateful so it can honour a one-shot
/// [highlightGameProvider] request (set by the QR scanner when the user declines
/// an overwrite): it scrolls the matching card into view and briefly flashes it.
class _SessionsList extends ConsumerStatefulWidget {
  const _SessionsList({required this.sessions});

  final List<GameSession> sessions;

  @override
  ConsumerState<_SessionsList> createState() => _SessionsListState();
}

class _SessionsListState extends ConsumerState<_SessionsList> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _flashKey = GlobalKey();
  String? _flashId;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startFlash(String id) {
    // Only react if the game is actually in the current list.
    if (!widget.sessions.any((s) => s.id == id)) {
      ref.read(highlightGameProvider.notifier).clear();
      return;
    }
    _flashTimer?.cancel();
    setState(() => _flashId = id);
    // Consume the one-shot signal now that it's captured in local state.
    ref.read(highlightGameProvider.notifier).clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _flashKey.currentContext;
      if (ctx != null) {
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.15,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          ),
        );
      }
    });
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  Future<void> _delete(GameSession session) async {
    // Capture the messenger BEFORE any awaits, so we don't depend on a context
    // that may change.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(gameHistoryProvider.notifier).deleteGame(session.id);
    showGameDeletedSnackBar(messenger, container, session);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ref.listen<String?>(highlightGameProvider, (_, next) {
      if (next != null) _startFlash(next);
    });

    final sessions = widget.sessions;
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // +1 for the "Spellen" header at index 0.
      itemCount: sessions.length + 1,
      // separator-i sits between item-i and item-(i+1): index 0 = below the
      // header (smaller gap), the rest = between cards.
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 8 : 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              header: true,
              child: Text(
                'Spellen',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }
        final session = sessions[index - 1];
        final isFlashing = session.id == _flashId;
        return _GameSessionCard(
          key: isFlashing ? _flashKey : null,
          session: session,
          highlight: isFlashing,
          onDelete: () => unawaited(_delete(session)),
        );
      },
    );
  }
}

// =============================================================================
// Storage-error screen — shared by game-history and settings error cases.
// All variable content (text, actions, storage key) is supplied by the caller.
// =============================================================================

enum _StorageErrorKind { unsupportedVersion, corrupt, unknown }

/// Classifies a persistence load failure into the kind that drives the shared
/// title / message / report-button selection. Shared by both error sources —
/// the two stores throw the same [PersistenceException] family — so the
/// exception→kind switch lives here once instead of in each call site.
_StorageErrorKind _kindFor(Object error) => switch (error) {
  UnsupportedVersionException() => _StorageErrorKind.unsupportedVersion,
  CorruptPersistenceException() => _StorageErrorKind.corrupt,
  _ => _StorageErrorKind.unknown,
};

/// Per-source variable content for the storage-error screen.
///
/// Everything that differs between the settings and game-history error flows —
/// the corrupt-kind title (the only title that varies by source), the three
/// messages, the storage key, and the clear/reset wiring — lives here. The
/// parts that are identical across sources (the unsupported-version and unknown
/// titles, and the report-button rule) stay in [_HomeErrorView], so a new error
/// kind or a change to the shared text is a one-place edit.
class _StorageErrorDescriptor {
  const _StorageErrorDescriptor({
    required this.corruptTitle,
    required this.unsupportedVersionMessage,
    required this.corruptMessage,
    required this.unknownMessage,
    required this.storageKey,
    required this.clearLabel,
    required this.clearConfirmTitle,
    required this.clearConfirmText,
    required this.clearIsDestructive,
    required this.onClear,
  });

  final String corruptTitle;
  final String unsupportedVersionMessage;
  final String corruptMessage;
  final String unknownMessage;
  final String storageKey;
  final String clearLabel;
  final String clearConfirmTitle;
  final String clearConfirmText;
  final bool clearIsDestructive;
  final Future<void> Function() onClear;
}

_StorageErrorDescriptor _settingsErrorDescriptor(WidgetRef ref) =>
    _StorageErrorDescriptor(
      corruptTitle: 'Instellingen beschadigd',
      unsupportedVersionMessage:
          'Je instellingen zijn opgeslagen door een nieuwere versie van '
          'de app en kunnen niet worden geladen. Update de app of wis de '
          'instellingen om verder te spelen.',
      corruptMessage:
          'Je instellingen kunnen niet worden gelezen (mogelijk '
          'beschadigd). Verstuur het foutrapport om dit probleem te melden, '
          'of wis de instellingen om verder te spelen.',
      unknownMessage:
          'Er is een onverwachte fout opgetreden bij het laden van de '
          'instellingen. Verstuur het foutrapport om dit probleem te '
          'melden, of wis de instellingen om verder te spelen.',
      storageKey: settingsStorageKey,
      clearLabel: 'Instellingen wissen',
      clearConfirmTitle: 'Instellingen wissen',
      clearConfirmText:
          'Je instellingen worden teruggezet naar de standaardwaarden.',
      clearIsDestructive: false,
      onClear: () async {
        await clearSettings();
        // Rebuild the single settings blob from its override (defaults, as
        // load failed) so the in-memory state matches the cleared storage.
        ref.invalidate(settingsProvider);
        ref.read(settingsLoadErrorProvider.notifier).clear();
      },
    );

_StorageErrorDescriptor _historyErrorDescriptor(WidgetRef ref) =>
    _StorageErrorDescriptor(
      corruptTitle: 'Geschiedenis beschadigd',
      unsupportedVersionMessage:
          'Je spelgeschiedenis is opgeslagen door een nieuwere versie van '
          'de app en kan niet worden geladen. Update de app om je '
          'geschiedenis te bekijken, of wis de geschiedenis om verder te '
          'spelen.',
      corruptMessage:
          'Je opgeslagen spelgeschiedenis kan niet worden gelezen (mogelijk '
          'beschadigd). Verstuur het foutrapport om dit probleem te melden, '
          'of wis de geschiedenis om verder te spelen.',
      unknownMessage:
          'Er is een onverwachte fout opgetreden bij het laden van de '
          'spelgeschiedenis. Verstuur het foutrapport om dit probleem te '
          'melden, of wis de geschiedenis om verder te spelen.',
      storageKey: GameHistoryNotifier.storageKey,
      clearLabel: 'Geschiedenis wissen',
      clearConfirmTitle: 'Geschiedenis wissen',
      clearConfirmText:
          'Alle gespeelde spellen worden permanent verwijderd. '
          'Dit kan niet ongedaan worden gemaakt.',
      clearIsDestructive: true,
      onClear: () => ref.read(gameHistoryProvider.notifier).clearHistory(),
    );

/// Full-screen storage-error view: an [appBar] (bare for the settings error so
/// its write actions can't touch the corrupt blob — CORR-style; full for the
/// history error) over a [_StorageErrorScreen] whose variable content comes from
/// [descriptor]. Classifying the error and projecting (kind → title / message /
/// report-button) happens here once, so the two call sites in [HomeScreen.build]
/// differ only by their descriptor and app bar.
class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({
    required this.appBar,
    required this.exception,
    required this.stackTrace,
    required this.descriptor,
  });

  final PreferredSizeWidget appBar;
  final Object exception;
  final StackTrace? stackTrace;
  final _StorageErrorDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final kind = _kindFor(exception);
    return AppScaffold(
      appBar: appBar,
      body: _StorageErrorScreen(
        title: switch (kind) {
          .unsupportedVersion => 'App bijwerken vereist',
          .corrupt => descriptor.corruptTitle,
          .unknown => 'Onbekende fout',
        },
        message: switch (kind) {
          .unsupportedVersion => descriptor.unsupportedVersionMessage,
          .corrupt => descriptor.corruptMessage,
          .unknown => descriptor.unknownMessage,
        },
        showReportButton: kind != _StorageErrorKind.unsupportedVersion,
        exception: exception,
        stackTrace: stackTrace,
        storageKey: descriptor.storageKey,
        clearLabel: descriptor.clearLabel,
        clearConfirmTitle: descriptor.clearConfirmTitle,
        clearConfirmText: descriptor.clearConfirmText,
        clearIsDestructive: descriptor.clearIsDestructive,
        onClear: descriptor.onClear,
      ),
    );
  }
}

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

    // Scrollable so the centred content (and especially the only recovery
    // buttons) can never be clipped at a large system text scale; the
    // ConstrainedBox keeps it vertically centred when it fits.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.error, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
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
                        _sendErrorReport(
                          context,
                          exception,
                          stackTrace,
                          storageKey,
                        ),
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
          ),
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

  final prefs = SharedPreferencesAsync();
  final rawData = await prefs.getString(storageKey);

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
  return 'Voeg hier je bericht toe (optioneel)...'
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
  const _GameSessionCard({
    super.key,
    required this.session,
    required this.onDelete,
    this.highlight = false,
  });

  final GameSession session;
  final VoidCallback onDelete;

  /// When true, a brief tinted overlay flags this card (see [_SessionsList]).
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void onTap() {
      holdCalculatorAcrossNavigation(context);
      ref.read(calculatorProvider.notifier).loadSession(session);
      unawaited(AppRoutes.openGame(context));
    }

    // Muted tint for the trailing Verwijderen IconButton (standard 48dp
    // tap target). Any future trailing icon inherits the same tint.
    final mutedIconTheme = mutedIconButtonTheme(
      theme,
      foregroundColor: theme.colorScheme.onSurfaceVariant,
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

    final card = Theme(
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

    // Brief "look here" flash after a declined overwrite: an animated coloured
    // outline around the card — the Material 3 way to draw attention without
    // obscuring its content. The border is always present so it animates both in
    // (on highlight) and out (fade to transparent when the flash clears);
    // ExcludeSemantics + IgnorePointer keep it purely decorative and tap-through,
    // and it sits in a Stack so the always-on 2px border never shifts the card's
    // layout.
    return Stack(
      children: [
        card,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: highlight
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withValues(alpha: 0),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
