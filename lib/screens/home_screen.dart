import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_session.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
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
    final historyAsync = ref.watch(gameHistoryProvider);

    return AppScaffold(
      appBar: AppBar(
        leading: const AboutIconButton(),
        title: const TitleWithRules(title: Text('Bonken')),
        actions: const [ThemeMenuButton()],
      ),
      body: historyAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => e is UnsupportedStorageVersionException
            ? const _UnsupportedVersionScreen()
            : const SizedBox.shrink(),
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
                            child: Text(
                              'Spellen',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    letterSpacing: 0.5,
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
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NewGameScreen(),
                      fullscreenDialog: true,
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
// Unsupported storage version screen
// =============================================================================

class _UnsupportedVersionScreen extends ConsumerWidget {
  const _UnsupportedVersionScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'App bijwerken vereist',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Je spelgeschiedenis is opgeslagen door een nieuwere versie van '
              'de app en kan niet worden geladen. Update de app om je '
              'geschiedenis te bekijken, of wis de geschiedenis om verder te '
              'spelen.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Geschiedenis wissen?',
                  contentText:
                      'Alle gespeelde spellen worden permanent verwijderd. '
                      'Dit kan niet ongedaan worden gemaakt.',
                  confirmLabel: 'Wissen',
                  destructive: true,
                );
                if (confirmed != true) return;
                await ref.read(gameHistoryProvider.notifier).clearHistory();
              },
              child: const Text('Geschiedenis wissen'),
            ),
          ],
        ),
      ),
    );
  }
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
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()));
    }

    // Muted tint for the trailing Verwijderen IconButton (standard 48dp
    // tap target). Any future trailing icon inherits the same tint.
    final mutedIconTheme = mutedIconButtonTheme(
      theme,
      foregroundColor: cs.onSurfaceVariant,
    );

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    final names = session.displayedPlayerNames.join(', ');
    final date = formatDate(session.updatedAt);
    final tapLabel = session.isFinished
        ? 'Afgerond spel met $names — $date'
        : 'Lopend spel met $names — ronde ${session.rounds.length + 1} '
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
        // Past-game card: date on the left, delete action on the right.
        headerLabel: Text(
          formatDate(session.updatedAt),
          style: labelStyle,
          overflow: TextOverflow.ellipsis,
        ),
        headerTrailing: IconButton(
          icon: const Icon(Symbols.delete),
          tooltip: 'Verwijderen',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
