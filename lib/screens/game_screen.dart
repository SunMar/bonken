import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_mechanics.dart';
import '../models/game_session.dart';
import '../models/games/game_catalog.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/round_record.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../theme/app_theme_extensions.dart';
import '../utils.dart';
import '../widgets/app_bar_widgets.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dealer_picker_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/doubles_chips.dart';
import '../widgets/game_avatar.dart';
import '../widgets/game_deleted_snackbar.dart';
import '../widgets/info_banner.dart';
import '../widgets/primary_action_button.dart';
import '../widgets/round_meta_line.dart';
import '../widgets/scoreboard_card.dart';
import 'edit_game_screen.dart';
import 'home_screen.dart';
import 'round_input_screen.dart';

// =============================================================================
// GameScreen — top-level screen
// =============================================================================

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const TitleWithRules(title: Text('Spel invoer'))),
      body: const _GameSelectionBody(),
    );
  }
}

/// Body of [GameScreen]: pickable mini-game tiles (grouped negative /
/// positive), the live scoreboard, and the round history.
///
/// Kept as a separate `ConsumerWidget` purely as a rebuild boundary — it
/// watches calculator state slices that change on every round, while the
/// surrounding [GameScreen] (AppBar + overflow menu) watches nothing and
/// stays put.
class _GameSelectionBody extends ConsumerStatefulWidget {
  const _GameSelectionBody();

  @override
  ConsumerState<_GameSelectionBody> createState() => _GameSelectionBodyState();
}

class _GameSelectionBodyState extends ConsumerState<_GameSelectionBody> {
  // Whether already-played games are revealed (normally hidden) per category.
  bool _showPlayedNegative = false;
  bool _showPlayedPositive = false;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(calculatorProvider.select((s) => s.history));
    final chooserId = ref.watch(calculatorProvider.select((s) => s.chooserId));
    final playedIds = history.map((r) => r.game.id).toSet();

    final isFinished = history.length >= GameSession.totalRounds;

    final negativeUnplayed = <MiniGame>[];
    final negativePlayed = <MiniGame>[];
    final positiveUnplayed = <MiniGame>[];
    final positivePlayed = <MiniGame>[];
    for (final g in allGames) {
      final played = playedIds.contains(g.id);
      final list = g.category == GameCategory.positive
          ? (played ? positivePlayed : positiveUnplayed)
          : (played ? negativePlayed : negativeUnplayed);
      list.add(g);
    }

    // Quota counts for the current chooser — computed once instead of
    // re-derived per tile via select().
    var negCount = 0;
    var posCount = 0;
    for (final r in history) {
      if (r.chooserId != chooserId) continue;
      if (r.game.category == GameCategory.negative) {
        negCount++;
      } else {
        posCount++;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _LiveScoreboard(),
        const SizedBox(height: 8),
        const _RoundInfoBanner(),
        if (isFinished) ...[
          const SizedBox(height: 12),
          // No Center wrapper here: the long label
          // "Nieuw spel met dezelfde spelers" would shrink-wrap to its
          // intrinsic (overflowing) width.  Letting the button take the
          // ListView's content width gives the label room to lay out.
          const _NewGameSamePlayersButton(),
        ],
        if (!isFinished) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Negatieve spellen',
            color: scoreColorNegative(context),
            canToggle: negativePlayed.isNotEmpty,
            showingPlayed: _showPlayedNegative,
            onToggle: () =>
                setState(() => _showPlayedNegative = !_showPlayedNegative),
          ),
          const SizedBox(height: 8),
          for (final game in negativeUnplayed)
            _GameTile(game: game, negCount: negCount, posCount: posCount),
          if (_showPlayedNegative)
            for (final game in negativePlayed)
              _GameTile(
                game: game,
                negCount: negCount,
                posCount: posCount,
                isPlayed: true,
              ),
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Positieve spellen',
            color: scoreColorPositive(context),
            canToggle: positivePlayed.isNotEmpty,
            showingPlayed: _showPlayedPositive,
            onToggle: () =>
                setState(() => _showPlayedPositive = !_showPlayedPositive),
          ),
          const SizedBox(height: 8),
          for (final game in positiveUnplayed)
            _GameTile(game: game, negCount: negCount, posCount: posCount),
          if (_showPlayedPositive)
            for (final game in positivePlayed)
              _GameTile(
                game: game,
                negCount: negCount,
                posCount: posCount,
                isPlayed: true,
              ),
        ],
        const SizedBox(height: 20),
        const _HistoryList(),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.color,
    required this.canToggle,
    required this.showingPlayed,
    required this.onToggle,
  });

  final String label;
  final Color color;

  /// Whether there are played games in this category to reveal. When false the
  /// toggle button renders disabled.
  final bool canToggle;
  final bool showingPlayed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            showingPlayed ? Symbols.visibility_off : Symbols.visibility,
          ),
          tooltip: showingPlayed
              ? 'Verberg gespeelde spellen'
              : 'Toon gespeelde spellen',
          onPressed: canToggle ? onToggle : null,
        ),
      ],
    );
  }
}

class _GameTile extends ConsumerWidget {
  const _GameTile({
    required this.game,
    required this.negCount,
    required this.posCount,
    this.isPlayed = false,
  });

  final MiniGame game;
  final int negCount;
  final int posCount;

  /// True for an already-played game revealed via the section's show-played
  /// toggle. Rendered disabled; tapping offers to force-replay it.
  final bool isPlayed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = game.category == GameCategory.positive;
    final textColor = scoreColor(isPositive ? 1 : -1, context);

    final pendingGameId = ref.watch(
      calculatorProvider.select((s) {
        final p = s.pending;
        return p is ActivePendingRound ? p.game.id : null;
      }),
    );
    final isPending = pendingGameId == game.id;
    final isPendingBlocked = pendingGameId != null && !isPending;

    final isQuotaDisabled = quotaReached(
      game.category,
      negativeChosen: negCount,
      positiveChosen: posCount,
    );

    final isDisabled =
        isPlayed || ((isPendingBlocked || isQuotaDisabled) && !isPending);

    // A dimmed-but-tappable tile is an override — announce why via a hint
    // (the ListTile already exposes the button role + game-name label).
    String? a11yHint;
    if (isPlayed) {
      a11yHint = 'Al gespeeld; activeer om opnieuw te spelen';
    } else if (isQuotaDisabled && !isPending) {
      a11yHint = 'Limiet bereikt; activeer om toch te kiezen';
    }

    final String subtitleText;
    if (isPending) {
      subtitleText = 'Niet afgerond  ·  tik om verder te gaan';
    } else if (isPlayed) {
      subtitleText = 'Spel al gespeeld';
    } else if (isPositive) {
      subtitleText = 'Positief  ·  +${game.totalPoints} punten totaal';
    } else {
      subtitleText = 'Negatief  ·  ${game.totalPoints} punten totaal';
    }

    final tile = Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: GameAvatar(game: game, radius: 22, disabled: isDisabled),
        title: Text(
          game.name,
          style: TextStyle(color: isDisabled ? disabledOnSurface(cs) : null),
        ),
        subtitle: Text(
          subtitleText,
          style: TextStyle(
            color: isDisabled ? disabledOnSurface(cs) : textColor,
          ),
        ),
        trailing: isPending
            ? Icon(Symbols.hourglass_top, color: cs.tertiary)
            : Icon(
                Symbols.chevron_right,
                color: isDisabled ? disabledOnSurface(cs) : null,
              ),
        onTap: () async {
          final state = ref.read(calculatorProvider);
          // Pending game tile — resume directly.
          if (isPending) {
            ref.read(calculatorProvider.notifier).selectGame(game);
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RoundInputScreen()),
            );
            return;
          }
          // Other games are blocked while a pending game exists.
          if (state.hasPendingGame) {
            await showInfoDialog(
              context,
              title: kRoundIncompleteTitle,
              contentText:
                  '${(state.pending as ActivePendingRound).game.name} is nog niet afgerond. '
                  'Maak dat spel eerst af, of verwerp het.',
            );
            return;
          }
          // Already-played games (revealed via the toggle) offer a replay.
          if (isPlayed) {
            final proceed = await showConfirmDialog(
              context,
              title: 'Spel al gespeeld',
              contentText:
                  '${game.name} is al gespeeld. Toch nog een keer spelen?',
              confirmLabel: 'Toch spelen',
            );
            if (!context.mounted) return;
            if (proceed != true) return;
          } else if (isQuotaDisabled) {
            // Quota-disabled games show a warning with an override option.
            final chooserName = state.playerNames[state.chooserIndex];
            final proceed = await showConfirmDialog(
              context,
              title: 'Limiet overschreden',
              contentText: game.category == GameCategory.negative
                  ? '$chooserName heeft al 2 negatieve spellen gekozen.'
                  : '$chooserName heeft al 1 positief spel gekozen.',
              confirmLabel: 'Toch doorgaan',
            );
            if (!context.mounted) return;
            if (proceed != true) return;
          }
          ref.read(calculatorProvider.notifier).selectGame(game);
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RoundInputScreen()),
          );
        },
      ),
    );
    return MergeSemantics(
      child: Semantics(button: true, hint: a11yHint, child: tile),
    );
  }
}

// =============================================================================
// Scoreboard — cumulative totals per player
// =============================================================================

class _LiveScoreboard extends ConsumerWidget {
  const _LiveScoreboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (history, displayedPlayers, updatedAt) = ref.watch(
      calculatorProvider.select(
        (s) => (s.history, s.displayedPlayers, s.updatedAt),
      ),
    );

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final roundsPlayed = history.length;
    final isFinished = roundsPlayed >= GameSession.totalRounds;

    // Sum scores per player across all completed rounds, in display order.
    final totals = List<int>.filled(playerCount, 0);
    for (final record in history) {
      for (int i = 0; i < playerCount; i++) {
        totals[i] += record.scoresByPlayer[displayedPlayers[i].id] ?? 0;
      }
    }

    // Winner indices (highest score, may be shared). Only highlighted
    // once the game is finished — mid-game leaders shouldn't claim the
    // crown yet.
    final best = totals.reduce((a, b) => a > b ? a : b);
    final winners = isFinished
        ? [
            for (int i = 0; i < playerCount; i++)
              if (totals[i] == best) i,
          ]
        : <int>[];

    // Muted tint for the trailing IconButtons, matching the home
    // session-card surface (standard 48dp tap targets).
    final mutedIconTheme = mutedIconButtonTheme(
      theme,
      foregroundColor: cs.onSurfaceVariant,
    );

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    // Same appearance as the home-screen session card: date on the
    // left, action(s) on the right. The game screen adds an
    // "Spel bewerken" icon next to the delete action.
    final headerLabel = updatedAt == null
        ? Text(isFinished ? 'Eindstand' : 'Tussenstand', style: labelStyle)
        : Text(
            formatDate(updatedAt),
            style: labelStyle,
            overflow: TextOverflow.ellipsis,
          );

    return Theme(
      data: mutedIconTheme,
      child: ScoreboardCard(
        roundsPlayed: roundsPlayed,
        playerNames: [for (final p in displayedPlayers) p.name],
        scores: totals,
        winners: winners,
        headerLabel: headerLabel,
        headerTrailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Symbols.edit),
              tooltip: 'Spel bewerken',
              onPressed: () {
                unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EditGameScreen(),
                      fullscreenDialog: true,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Symbols.delete),
              tooltip: 'Spel verwijderen',
              onPressed: () => _deleteGame(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  // Delete-and-undo flow:
  //   1. Snapshot the GameSession BEFORE the delete, so the snackbar's
  //      undo can re-save it byte-for-byte.
  //   2. Capture the ScaffoldMessenger + root ProviderContainer BEFORE
  //      any await — both must outlive this widget, which gets disposed
  //      by pushAndRemoveUntil below.
  //   3. Delete from history, reset the calculator, then navigate to
  //      HomeScreen.
  //   4. Show the snackbar AFTER the navigation so it anchors to the
  //      freshly-mounted HomeScreen.
  Future<void> _deleteGame(BuildContext context, WidgetRef ref) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Spel verwijderen?',
      contentText: 'Dit spel wordt permanent verwijderd uit de geschiedenis.',
      confirmLabel: 'Verwijderen',
      destructive: true,
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final session = ref.read(calculatorProvider.notifier).buildSession();
    final sessionId = ref.read(calculatorProvider).sessionId;
    await ref.read(gameHistoryProvider.notifier).deleteGame(sessionId);
    if (!context.mounted) return;
    ref.read(calculatorProvider.notifier).reset();
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (_) => false,
      ),
    );
    if (session != null) {
      showGameDeletedSnackBar(messenger, container, session);
    }
  }
}

class _NewGameSamePlayersButton extends ConsumerWidget {
  const _NewGameSamePlayersButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrimaryActionButton(
      icon: const Icon(Symbols.replay),
      label: const Text('Nieuw spel met dezelfde spelers'),
      onPressed: () => _onPressed(context, ref),
    );
  }

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    final state = ref.read(calculatorProvider);
    final names = List<String>.from(state.playerNames);
    final previousDealer = state.dealerIndex;

    final pick = await showDealerPickerDialog(
      context,
      playerNames: names,
      previousDealerIndex: previousDealer,
    );
    if (pick == null) return;
    if (!context.mounted) return;

    int dealerIndex;
    DealerAnnouncementKind? announceKind;
    switch (pick) {
      case NextDealerNext():
        dealerIndex = (previousDealer + 1) % playerCount;
        announceKind = DealerAnnouncementKind.next;
      case NextDealerRandom():
        dealerIndex = Random().nextInt(playerCount);
        announceKind = DealerAnnouncementKind.random;
      case NextDealerSpecific(:final index):
        dealerIndex = index;
        announceKind = null;
    }

    if (announceKind != null) {
      await showDealerAnnouncementDialog(
        context,
        dealerName: names[dealerIndex],
        kind: announceKind,
      );
      if (!context.mounted) return;
    }

    final notifier = ref.read(calculatorProvider.notifier);
    final newPlayers = [for (final name in names) Player(name: name)];
    notifier.startNewGame(
      players: newPlayers,
      dealerIndex: dealerIndex,
      // Carry over the just-finished game's house rules so the repeated game
      // doesn't silently reset to hardcoded defaults.
      ruleVariants: state.ruleVariants,
    );
    final session = notifier.buildSession();
    if (session != null) {
      await ref.read(gameHistoryProvider.notifier).saveGame(session);
    }
    // Stay on the calculator screen — startNewGame already reset state to
    // a fresh game-selection phase, so the screen rebuilds accordingly.
  }
}

// =============================================================================
// History list — compact log of completed rounds
// =============================================================================

class _HistoryList extends ConsumerWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow subscription: rebuild only when one of these slices changes,
    // not on every input keystroke / chooser tap / etc. The list of player
    // names is referenced by every row but stays constant during gameplay.
    final (history, displayedPlayers, hasPendingGame) = ref.watch(
      calculatorProvider.select(
        (s) => (s.history, s.displayedPlayers, s.hasPendingGame),
      ),
    );
    if (history.isEmpty) return const SizedBox.shrink();

    final displayedNames = [for (final p in displayedPlayers) p.name];

    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(calculatorProvider.notifier);

    // Normal mode: reversed (most recent first), with edit buttons.
    final lastRoundNumber = history.last.roundNumber;
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Gespeelde rondes',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final record in history.reversed) ...[
                const Divider(height: 16),
                _HistoryRow(
                  record: record,
                  playerNames: displayedNames,
                  players: displayedPlayers,
                  cs: cs,
                  notifier: notifier,
                  showDelete:
                      record.roundNumber == lastRoundNumber && !hasPendingGame,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single row in [_HistoryList].
///
/// Extracted as a const-friendly widget so iterating over reversed history
/// produces independent subtrees that won't all rebuild together.
///
/// Only the most recent round shows a delete button.  The edit icon sits at
/// the top of the trailing column, so non-last rows simply omit the delete
/// button and let the row collapse to its natural height.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.record,
    required this.playerNames,
    required this.players,
    required this.cs,
    required this.notifier,
    required this.showDelete,
  });

  final RoundRecord record;
  final List<String> playerNames;
  final List<Player> players;
  final ColorScheme cs;
  final CalculatorNotifier notifier;
  final bool showDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final safeChooserIdx = seatIndexOf(players, record.chooserId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Round + game
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoundRowHeader(
                record: record,
                playerNames: playerNames,
                cs: cs,
                chooserIndex: safeChooserIdx,
              ),
              if (record.doubles.hasAnyDouble)
                DoublesChips(
                  doubles: record.doubles,
                  players: players,
                  chooserIndex: safeChooserIdx,
                ),
            ],
          ),
        ),
        // Per-player deltas — names right-aligned, scores right-aligned.
        // We keep IntrinsicWidth here on purpose: a fixed score-column
        // width would either crowd extreme scores or waste horizontal
        // space for normal scores. With at most 12 rounds in a Bonken
        // game the extra layout pass per row is negligible.
        IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < playerCount; i++)
                    Text(
                      '${playerNames[i]}:',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < playerCount; i++)
                    Text(
                      formatScore(record.scoresByPlayer[players[i].id] ?? 0),
                      style: tt.bodyMedium?.copyWith(
                        color: scoreColor(
                          record.scoresByPlayer[players[i].id] ?? 0,
                          context,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Edit + (optional) delete buttons.  Only the most recent round
        // gets a delete button; non-last rows just show edit and the row
        // collapses to its natural height.  Buttons are standard 48dp targets.
        Column(
          children: [
            IconButton(
              icon: const Icon(Symbols.edit),
              tooltip: 'Wijzigen',
              onPressed: () {
                notifier.restoreRound(record);
                unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RoundInputScreen(),
                    ),
                  ),
                );
              },
            ),
            if (showDelete)
              IconButton(
                icon: const Icon(Symbols.delete),
                tooltip: 'Ronde verwijderen',
                onPressed: () async {
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Ronde verwijderen?',
                    contentText:
                        'Ronde ${record.roundNumber} (${record.game.name}) '
                        'wordt permanent verwijderd.',
                    confirmLabel: 'Verwijderen',
                    destructive: true,
                  );
                  if (confirm != true) return;
                  notifier.deleteLastRound();
                },
              ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Round info banner — shown in the game selection phase
// =============================================================================

class _RoundInfoBanner extends ConsumerWidget {
  const _RoundInfoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow watch: only the five derived values shown here, not the whole
    // state — keeps the banner off the per-keystroke rebuild path.
    final (round, dealerName, chooserName, starterName, roundsPlayed) = ref
        .watch(
          calculatorProvider.select(
            (s) => (
              s.roundNumber,
              s.playerNames[s.dealerIndex],
              s.playerNames[(s.dealerIndex + 1) % playerCount],
              s.playerNames[s.starterIndex],
              s.history.length,
            ),
          ),
        );
    final cs = Theme.of(context).colorScheme;

    // Hide once all rounds are done.
    if (roundsPlayed >= GameSession.totalRounds) {
      return const SizedBox.shrink();
    }

    return InfoBanner(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ronde $round van ${GameSession.totalRounds}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            RoundMetaLine(
              color: cs.onSecondaryContainer,
              segments: [
                'Kiezer: $chooserName',
                'Deler: $dealerName',
                'Uitkomst: $starterName',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "Ronde N — game name / chooser name" row used by [_HistoryList].
class _RoundRowHeader extends StatelessWidget {
  const _RoundRowHeader({
    required this.record,
    required this.playerNames,
    required this.cs,
    required this.chooserIndex,
  });

  final RoundRecord record;
  final List<String> playerNames;
  final ColorScheme cs;
  final int chooserIndex;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ronde ${record.roundNumber} — ${record.game.name}',
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          playerNames[chooserIndex],
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
