import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mini_game.dart';

import '../models/game_session.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../state/theme_mode_provider.dart';
import '../utils.dart';
import 'calculator_screen.dart';
import 'setup_screen.dart';

/// Home screen: logo, past-games list, and "Nieuw spel" button.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(gameHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----------------------------------------------------------------
            // Logo / title area
            // ----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: const AssetImage(
                      'assets/icon/icon_bonken.png',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonken',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Scorekaart',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ThemeModeButton(),
                ],
              ),
            ),

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
                  return ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'Spellen',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                        ),
                      ),
                      for (final session in sessions)
                        _GameSessionCard(
                          session: session,
                          onDelete: () async {
                            // Capture the messenger BEFORE any awaits, so we
                            // don't depend on a context that may change.
                            final messenger = ScaffoldMessenger.of(context);
                            await ref
                                .read(gameHistoryProvider.notifier)
                                .deleteGame(session.id);
                            messenger.hideCurrentSnackBar();
                            final controller = messenger.showSnackBar(
                              SnackBar(
                                content: const Text('Spel verwijderd'),
                                duration: const Duration(seconds: 5),
                                action: SnackBarAction(
                                  label: 'Ongedaan maken',
                                  onPressed: () {
                                    ref
                                        .read(gameHistoryProvider.notifier)
                                        .saveGame(session);
                                  },
                                ),
                              ),
                            );
                            // Belt-and-suspenders: SnackBar's built-in
                            // auto-dismiss timer doesn't always fire (esp. on
                            // web).  Force-close it after the duration.
                            Timer(const Duration(seconds: 5), () {
                              controller.close();
                            });
                          },
                        ),
                    ],
                  );
                },
              ),
            ),

            // ----------------------------------------------------------------
            // New-game button (always pinned at bottom)
            // ----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nieuw spel'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
                onPressed: () {
                  ref.read(calculatorProvider.notifier).reset();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SetupScreen()),
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
// Past-game card
// =============================================================================

class _GameSessionCard extends ConsumerWidget {
  const _GameSessionCard({required this.session, required this.onDelete});

  final GameSession session;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final scores = session.finalScores;
    final winners = session.isFinished ? session.winnerIndices : <int>[];

    void onTap() {
      ref.read(calculatorProvider.notifier).loadSession(session);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CalculatorScreen()));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date + rounds played + status
              Row(
                children: [
                  Icon(
                    session.isFinished
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                    size: 16,
                    color: session.isFinished
                        ? successGreen
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatDate(session.updatedAt),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      color: cs.onSurfaceVariant,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Verwijderen',
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Player scores (4 columns)
              Row(
                children: [
                  for (int i = 0; i < playerCount; i++)
                    Expanded(
                      child: _PlayerScoreChip(
                        name: session.playerNames[i],
                        score: scores[i] ?? 0,
                        isWinner: winners.contains(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerScoreChip extends StatelessWidget {
  const _PlayerScoreChip({
    required this.name,
    required this.score,
    required this.isWinner,
  });

  final String name;
  final int score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: isWinner
          ? BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Column(
        children: [
          if (isWinner) ...[
            Icon(Icons.emoji_events, size: 14, color: cs.primary),
            const SizedBox(height: 2),
          ],
          Text(
            name,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: isWinner ? FontWeight.bold : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatScore(score),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: scoreColor(score, cs),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeButton extends ConsumerWidget {
  const _ThemeModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.system => Icons.contrast,
    };

    return PopupMenuButton<ThemeMode>(
      icon: Icon(icon),
      tooltip: 'Thema',
      onSelected: (value) =>
          ref.read(themeModeProvider.notifier).setMode(value),
      itemBuilder: (_) => [
        _themeModeItem(ThemeMode.system, Icons.contrast, 'Systeem', mode),
        _themeModeItem(ThemeMode.light, Icons.light_mode, 'Licht', mode),
        _themeModeItem(ThemeMode.dark, Icons.dark_mode, 'Donker', mode),
      ],
    );
  }

  PopupMenuItem<ThemeMode> _themeModeItem(
    ThemeMode value,
    IconData icon,
    String label,
    ThemeMode current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(label),
          if (value == current) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16),
          ],
        ],
      ),
    );
  }
}
