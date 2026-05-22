import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/games/game_catalog.dart';
import '../models/game_session.dart';
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
import '../widgets/game_deleted_snackbar.dart';
import '../widgets/scoreboard_card.dart';
import '../widgets/primary_action_button.dart';
import 'home_screen.dart';
import 'edit_players_screen.dart';
import 'round_input_screen.dart';

// Per-suit accent colors live in [GameSuitColors] (a `ThemeExtension`)
// so they can be themed/overridden alongside the rest of the palette.
// See `lib/theme/app_theme_extensions.dart`.

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
class _GameSelectionBody extends ConsumerWidget {
  const _GameSelectionBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(calculatorProvider.select((s) => s.history));
    final chooserId = ref.watch(calculatorProvider.select((s) => s.chooserId));
    final playedIds = history.map((r) => r.game.id).toSet();

    final isFinished = history.length >= GameSession.totalRounds;

    final positiveGames = <MiniGame>[];
    final negativeGames = <MiniGame>[];
    for (final g in allGames) {
      if (playedIds.contains(g.id)) continue;
      if (g.category == GameCategory.positive) {
        positiveGames.add(g);
      } else {
        negativeGames.add(g);
      }
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
        if (!isFinished && negativeGames.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Negatieve spellen',
            color: scoreColorNegative(context),
          ),
          const SizedBox(height: 8),
          for (final game in negativeGames)
            _GameTile(game: game, negCount: negCount, posCount: posCount),
        ],
        if (!isFinished && positiveGames.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Positieve spellen',
            color: scoreColorPositive(context),
          ),
          const SizedBox(height: 8),
          for (final game in positiveGames)
            _GameTile(game: game, negCount: negCount, posCount: posCount),
        ],
        const SizedBox(height: 20),
        const _HistoryList(),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: color, letterSpacing: 0.5),
    );
  }
}

class _GameTile extends ConsumerWidget {
  const _GameTile({
    required this.game,
    required this.negCount,
    required this.posCount,
  });

  final MiniGame game;
  final int negCount;
  final int posCount;

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

    final isQuotaDisabled =
        (game.category == GameCategory.negative && negCount >= 2) ||
        (game.category == GameCategory.positive && posCount >= 1);

    final isDisabled = (isPendingBlocked || isQuotaDisabled) && !isPending;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: GameAvatar(game: game, radius: 22, disabled: isDisabled),
        title: Text(
          game.name,
          style: TextStyle(color: isDisabled ? disabledOnSurface(cs) : null),
        ),
        subtitle: Text(
          isPending
              ? 'Niet afgerond  ·  tik om verder te gaan'
              : isPositive
              ? 'Positief  ·  +${game.totalPoints} punten totaal'
              : 'Negatief  ·  ${game.totalPoints} punten totaal',
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
                  'Maak dat spel eerst af.',
            );
            return;
          }
          // Quota-disabled games show a warning with an override option.
          if (isQuotaDisabled) {
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

    // Compact density for the trailing IconButtons, matching the
    // history-card and home session-card surfaces.
    final compactIconTheme = compactIconButtonTheme(
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
      data: compactIconTheme,
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
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EditPlayersScreen(),
                    fullscreenDialog: true,
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
    notifier.startNewGame(players: newPlayers, dealerIndex: dealerIndex);
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
    // Theme-scoped compact density for everything in this card.  The history
    // card is a "data-dense list" surface (Material's term), so trailing
    // IconButtons inherit Material 3's `small` size variant (~32dp slot,
    // 18dp glyph) instead of the default 48dp touch target.  Individual
    // IconButtons below stay free of size/density overrides.
    final compactIconTheme = compactIconButtonTheme(theme);
    return RepaintBoundary(
      child: Theme(
        data: compactIconTheme,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gespeelde rondes', style: theme.textTheme.titleSmall),
                for (final record in history.reversed) ...[
                  const Divider(height: 16),
                  _HistoryRow(
                    record: record,
                    playerNames: displayedNames,
                    players: displayedPlayers,
                    cs: cs,
                    notifier: notifier,
                    showDelete:
                        record.roundNumber == lastRoundNumber &&
                        !hasPendingGame,
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
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
        // collapses to its natural height.  Size/density come from the
        // compact IconButtonTheme installed on the surrounding card.
        Column(
          children: [
            IconButton(
              icon: const Icon(Symbols.edit),
              tooltip: 'Wijzigen',
              onPressed: () {
                notifier.restoreRound(record);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RoundInputScreen(),
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
    final state = ref.watch(calculatorProvider);
    final cs = Theme.of(context).colorScheme;
    final round = state.roundNumber;
    final dealerName = state.playerNames[state.dealerIndex];
    final chooserName =
        state.playerNames[(state.dealerIndex + 1) % playerCount];

    // Hide once all rounds are done.
    if (state.history.length >= GameSession.totalRounds) {
      return const SizedBox.shrink();
    }

    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Symbols.info, size: 18, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
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
                  Text(
                    'Deler: $dealerName  ·  Kiezer: $chooserName',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
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

/// Circular avatar showing a mini-game's symbol with its accent color.
class GameAvatar extends StatelessWidget {
  const GameAvatar({
    required this.game,
    required this.radius,
    this.disabled = false,
    super.key,
  });

  final MiniGame game;
  final double radius;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suits =
        Theme.of(context).extension<GameSuitColors>() ??
        GameSuitColors.standard;
    final isPositive = game.category == GameCategory.positive;
    final textColor = scoreColor(isPositive ? 1 : -1, context);
    final symbolColor = suits.forGameId(game.id) ?? textColor;
    return CircleAvatar(
      radius: radius,
      backgroundColor: symbolColor.withValues(alpha: disabled ? 0.06 : 0.12),
      child: _GameSymbol(
        symbol: game.symbol,
        color: disabled ? disabledOnSurface(cs) : symbolColor,
        fontSize: 16,
      ),
    );
  }
}

/// Renders a [GameSymbol]: a [TextSymbol] renders as bold text, a
/// [SuitSymbol] renders as a card-suit glyph in DejaVu Sans (so the
/// glyph matches the launcher icons and isn't substituted for a colored
/// emoji on Android), and an [IconSymbol] renders as a Material Symbols
/// vector glyph sized to roughly match the cap height of adjacent text.
/// The `switch` arms below are intentionally ordered to match this doc.
class _GameSymbol extends StatelessWidget {
  const _GameSymbol({
    required this.symbol,
    required this.color,
    required this.fontSize,
  });

  final GameSymbol symbol;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Sealed-class switch: adding a fourth [GameSymbol] variant in the
    // model layer would make this expression fail to compile until a
    // branch is added here, which is the whole point of the sealed-class
    // refactor.
    return switch (symbol) {
      TextSymbol(:final text) => Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
      IconSymbol(:final icon) => Icon(
        icon,
        // Icon size matches the cap height of adjacent letters. Unlike
        // [Text], [Icon] does not honor the user's accessibility text
        // scale automatically, so we apply [MediaQuery.textScalerOf]
        // manually to keep icon and text avatars visually consistent.
        size: MediaQuery.textScalerOf(context).scale(fontSize) * 1.1,
        color: color,
        // `fill: 1` renders Material Symbols (a variable font) in their
        // filled variant.
        fill: 1,
      ),
      SuitSymbol(:final text) => Text(
        text,
        style: TextStyle(
          color: color,
          // Bundled DejaVu Sans, regular weight — matches the suits in
          // the launcher icons (rendered from the same .ttf by
          // tool/generate_icons.sh) and avoids Android substituting
          // colored emoji for these codepoints.
          fontFamily: 'DejaVu Sans',
          fontWeight: FontWeight.normal,
          // The suit glyphs in DejaVu Sans don't fill the em-box the way
          // letter glyphs do, so they look noticeably smaller than the
          // text variants at the same nominal size. Scale up so suit
          // glyphs read at the same visual weight as letter glyphs at
          // the same nominal `fontSize`. The user's accessibility text
          // scale is still applied automatically by [Text] on top of
          // this static design multiplier.
          fontSize: fontSize * 1.4,
        ),
      ),
    };
  }
}
