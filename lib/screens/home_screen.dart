import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mini_game.dart';

import '../models/game_session.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----------------------------------------------------------------
          // History list (or placeholder)
          // ----------------------------------------------------------------
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const SizedBox.shrink(),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Text(
                      'Nog geen gespeelde spellen',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.separated(
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
                        showGameDeletedSnackBar(messenger, container, session);
                      },
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
    final scores = session.finalScores;
    final winners = session.isFinished ? session.winnerIndices : <int>[];

    void onTap() {
      ref.read(calculatorProvider.notifier).loadSession(session);
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const GameScreen()));
    }

    // Compact density for the trailing Verwijderen IconButton (32×32
    // slot / 18dp glyph). Any future trailing icon (e.g. share, archive)
    // inherits the same size without per-button overrides.
    final compactIconTheme = compactIconButtonTheme(
      theme,
      foregroundColor: cs.onSurfaceVariant,
    );

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Theme(
      data: compactIconTheme,
      child: ScoreboardCard(
        // Zero outer margin so the ListView's separator owns all
        // vertical spacing between cards (avoids the default Card
        // margin compounding with the separator gap).
        margin: EdgeInsets.zero,
        roundsPlayed: session.rounds.length,
        playerNames: session.playerNames,
        scores: [for (int i = 0; i < playerCount; i++) scores[i] ?? 0],
        winners: winners,
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
