import 'dart:async';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_mechanics.dart';
import '../models/game_session.dart';
import '../models/games/game_catalog.dart';
import '../models/mini_game.dart';
import '../models/player.dart';
import '../models/round_record.dart';
import '../services/share_service.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../state/platform_io_providers.dart';
import '../state/rules_edit_mode_provider.dart';
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
import '../widgets/round_meta_line.dart';
import '../widgets/scoreboard_card.dart';
import '../widgets/timed_snackbar.dart';
import 'edit_game_screen.dart';
import 'round_input_screen.dart';

// =============================================================================
// GameScreen — top-level screen
// =============================================================================

enum _ShareDialogResult { shareImage, shareText, saveImage, copyText }

/// Players ranked highest score first for the share views. Ties keep the
/// players' seat (display) order so the output is deterministic across renders
/// and app restarts — Bonken has no rule-level tiebreak, this is purely for a
/// stable list order.
@visibleForTesting
List<({String name, int score, int seat})> rankScores(
  List<RoundRecord> history,
  List<Player> displayedPlayers,
) {
  final totals = cumulativeTotals(history, displayedPlayers);
  return [
    for (int i = 0; i < displayedPlayers.length; i++)
      (name: displayedPlayers[i].name, score: totals[i], seat: i),
  ]..sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.seat.compareTo(b.seat);
  });
}

/// Builds the plain-text share payload from already-ranked [entries] (highest
/// first). Pure (no provider access) so it is unit-testable; the top score gets
/// the 🏆 (ties shared).
@visibleForTesting
String buildShareText({
  String? gameName,
  required DateTime scoredAt,
  required List<({String name, int score, int seat})> entries,
}) {
  final maxScore = entries.isEmpty ? 0 : entries.first.score;
  final lines = [
    'Bonken uitslag',
    ?gameName,
    formatDate(scoredAt),
    for (final e in entries)
      '${e.name}  ${e.score} pt${e.score == maxScore ? ' 🏆' : ''}',
  ];
  return lines.join('\n');
}

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  // ref.read and Notifier.state are both invalid in dispose(); capture the
  // container and notifier in initState so dispose() can use them safely.
  late ProviderContainer _container;
  late CalculatorNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _notifier = ref.read(calculatorProvider.notifier);
  }

  @override
  void dispose() {
    // Riverpod cancels ref.watch subscriptions only after dispose() returns
    // (in ConsumerStatefulElement.unmount). Calling flushAndReset() directly
    // would flip the state to NoSession while activeSessionProvider (and the
    // selects reading it) still hold ActiveSession casts → CastError. The
    // post-frame callback fires after finalizeTree() has cancelled all
    // subscriptions and autoDisposed activeSessionProvider, so the state change
    // lands safely. The sessionId guard prevents resetting a session that was
    // loaded between the pop and the callback.
    final s = _container.read(calculatorProvider);
    if (s is ActiveSession) {
      final sessionId = s.sessionId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = _container.read(calculatorProvider);
        if (current is ActiveSession && current.sessionId == sessionId) {
          _notifier.flushAndReset();
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starterVariant = ref.watch(
      activeSessionProvider.select((a) => a.ruleVariants.starterVariant),
    );
    final heartsVariant = ref.watch(
      activeSessionProvider.select((a) => a.ruleVariants.heartsVariant),
    );
    final isFinished = ref.watch(
      activeSessionProvider.select(
        (a) => a.history.length >= GameSession.totalRounds,
      ),
    );

    return AppScaffold(
      appBar: AppBar(
        title: TitleWithRules(
          title: const Text('Spel invoer'),
          starterVariantOverride: starterVariant,
          heartsVariantOverride: heartsVariant,
          editMode: RulesEditMode.disabled,
        ),
        actions: [if (isFinished) _buildShareAction()],
      ),
      body: const _GameSelectionBody(),
    );
  }

  /// The finished-game share action. A plain tap shares with the default format
  /// (image, falling back to text); a long-press (touch) or a screen-reader
  /// custom action opens the format picker — a niche affordance, so it stays out
  /// of the way of the common case.
  Widget _buildShareAction() {
    return TooltipTheme(
      // `manual` disables only the *touch* trigger, so a long-press opens the
      // dialog without the tooltip racing it; mouse hover still shows it.
      data: TooltipTheme.of(
        context,
      ).copyWith(triggerMode: TooltipTriggerMode.manual),
      // Merge so the long-press (GestureDetector) and the custom actions fold
      // into the IconButton's single labeled button node — otherwise the
      // long-press would surface as a separate, unlabeled tappable node.
      child: MergeSemantics(
        child: Semantics(
          customSemanticsActions: {
            const CustomSemanticsAction(label: 'Deel als afbeelding'): () =>
                unawaited(_shareImage()),
            const CustomSemanticsAction(label: 'Deel als tekst'): () =>
                unawaited(_shareText()),
            const CustomSemanticsAction(label: 'Bewaar als afbeelding'): () =>
                unawaited(_saveImage()),
            const CustomSemanticsAction(label: 'Kopieer als tekst'): () =>
                unawaited(_copyText()),
          },
          child: GestureDetector(
            onLongPress: () => unawaited(_showShareDialog()),
            child: IconButton(
              icon: const Icon(Symbols.share),
              tooltip: 'Deel uitslag',
              onPressed: () => unawaited(_share()),
            ),
          ),
        ),
      ),
    );
  }

  /// Popup dialog (consistent with the app's dialog/popup convention — no menus)
  /// letting the user pick format and action. Reached by long-press or the
  /// screen-reader custom action; a plain tap never opens it.
  Future<void> _showShareDialog() async {
    final result = await showDialog<_ShareDialogResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Zero horizontal padding so the option rows span the dialog width;
        // each ListTile keeps its own inset.
        semanticLabel: 'Uitslag delen',
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        actionsPadding: const EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          bottom: 8,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.image),
              title: const Text('Afbeelding'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Symbols.share),
                    tooltip: 'Afbeelding delen',
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_ShareDialogResult.shareImage),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.download),
                    tooltip: 'Afbeelding opslaan',
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_ShareDialogResult.saveImage),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.article),
              title: const Text('Tekst'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Symbols.share),
                    tooltip: 'Tekst delen',
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_ShareDialogResult.shareText),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.content_copy),
                    tooltip: 'Tekst kopiëren',
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_ShareDialogResult.copyText),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuleren'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case _ShareDialogResult.shareImage:
        await _shareImage();
      case _ShareDialogResult.shareText:
        await _shareText();
      case _ShareDialogResult.saveImage:
        await _saveImage();
      case _ShareDialogResult.copyText:
        await _copyText();
    }
  }

  /// Shares the result as an image only (no silent text fallback) — used by the
  /// explicit "Afbeelding" choice, which should report failure rather than
  /// quietly switch formats.
  Future<void> _shareImage() => _share(fallbackToText: false);

  Future<void> _share({bool fallbackToText = true}) async {
    // Read the provider before the capture await: ref is unsafe once the widget
    // is unmounted (e.g. the user navigates away mid-capture).
    final share = ref.read(shareFileProvider);
    final text = _buildShareText();
    final Uint8List? bytes = await _captureShareCard();
    if (bytes != null) {
      final shared = await share(
        bytes: bytes,
        filename: 'bonken-uitslag.png',
        mimeType: 'image/png',
        subject: 'Bonken uitslag',
        text: text,
      );
      if (shared) return;
      // Image share not supported (e.g. Web Share API Level 2 unavailable).
      if (!fallbackToText && mounted) {
        showTimedSnackBar(
          ScaffoldMessenger.of(context),
          content: const Text(
            'Afbeelding delen wordt niet ondersteund op dit apparaat.',
          ),
        );
      }
    }
    if (fallbackToText && mounted) await _shareText();
  }

  Future<void> _shareText() async {
    final shared = await ref.read(shareTextProvider)(
      text: _buildShareText(),
      subject: 'Bonken uitslag',
    );
    if (!shared && mounted) {
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: const Text(kShareUnsupportedMessage),
      );
    }
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: _buildShareText()));
    if (!mounted) return;
    showTimedSnackBar(
      ScaffoldMessenger.of(context),
      content: const Text('Tekst gekopieerd naar klembord'),
    );
  }

  Future<void> _saveImage() async {
    final scoredAt = ref.read(activeSessionProvider).scoredAt;
    final save = ref.read(saveImageFileProvider);
    final bytes = await _captureShareCard();
    if (bytes == null || !mounted) return;
    try {
      final saved = await save(
        bytes: bytes,
        filename: 'bonken-uitslag-${formatFileDate(scoredAt)}.png',
      );
      if (!mounted) return;
      if (saved && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        showTimedSnackBar(
          ScaffoldMessenger.of(context),
          content: const Text('Afbeelding opgeslagen in Bestanden → Bonken'),
        );
      }
    } on Object {
      if (!mounted) return;
      showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: const Text('Het is mislukt om de afbeelding op te slaan.'),
      );
    }
  }

  /// Renders [_ShareCard] off-screen just long enough to capture it as a PNG,
  /// then removes it. Built on demand (only when an image is actually needed)
  /// via an [OverlayEntry] rather than permanently composited. Returns null if
  /// rendering/capture fails.
  Future<Uint8List?> _captureShareCard() async {
    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context);
    final mediaQuery = MediaQuery.of(context);
    final entry = OverlayEntry(
      // Off-screen (clipped to zero size) and excluded from the a11y tree, but a
      // real composited layer so toImage() captures it. textScaler is pinned so
      // the exported image is independent of the user's font-scale setting.
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: ExcludeSemantics(
          child: ClipRect(
            child: SizedBox.shrink(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: MediaQuery(
                    data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
                    child: const _ShareCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // Let the entry lay out and paint before capturing.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final object = boundaryKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;
      final image = await object.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } on Object catch (_) {
      return null;
    } finally {
      entry.remove();
    }
  }

  String _buildShareText() {
    final session = ref.read(activeSessionProvider);
    return buildShareText(
      gameName: session.gameName,
      scoredAt: session.scoredAt,
      entries: rankScores(session.history, session.displayedPlayers),
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
    final history = ref.watch(activeSessionProvider.select((a) => a.history));
    final chooserId = ref.watch(
      activeSessionProvider.select((a) => a.chooserId),
    );
    final playedIds = history.map((r) => r.game.id).toSet();

    final isFinished = history.length >= GameSession.totalRounds;

    final negativeGames = <MiniGame>[];
    final positiveGames = <MiniGame>[];
    var negativePlayed = 0;
    var positivePlayed = 0;
    for (final g in allGames) {
      final played = playedIds.contains(g.id);
      if (g.category == GameCategory.positive) {
        positiveGames.add(g);
        if (played) positivePlayed++;
      } else {
        negativeGames.add(g);
        if (played) negativePlayed++;
      }
    }

    final allNegativesPlayed = negativePlayed == negativeGames.length;
    final allPositivesPlayed = positivePlayed == positiveGames.length;

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
            canToggle: negativePlayed > 0,
            showingPlayed: _showPlayedNegative,
            onToggle: () =>
                setState(() => _showPlayedNegative = !_showPlayedNegative),
          ),
          const SizedBox(height: 8),
          if (allNegativesPlayed && !_showPlayedNegative)
            const _AllGamesPlayedCard(
              title: 'Alle negatieve spellen zijn gespeeld',
            ),
          for (final game in negativeGames)
            if (!playedIds.contains(game.id) || _showPlayedNegative)
              _GameTile(
                game: game,
                negCount: negCount,
                posCount: posCount,
                isPlayed: playedIds.contains(game.id),
              ),
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Positieve spellen',
            color: scoreColorPositive(context),
            canToggle: positivePlayed > 0,
            showingPlayed: _showPlayedPositive,
            onToggle: () =>
                setState(() => _showPlayedPositive = !_showPlayedPositive),
          ),
          const SizedBox(height: 8),
          if (allPositivesPlayed && !_showPlayedPositive)
            const _AllGamesPlayedCard(
              title: 'Alle positieve spellen zijn gespeeld',
            ),
          for (final game in positiveGames)
            if (!playedIds.contains(game.id) || _showPlayedPositive)
              _GameTile(
                game: game,
                negCount: negCount,
                posCount: posCount,
                isPlayed: playedIds.contains(game.id),
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

class _AllGamesPlayedCard extends StatelessWidget {
  const _AllGamesPlayedCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dimColor = disabledOnSurface(cs);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(
          start: 16,
          end: 24,
          top: 6,
          bottom: 6,
        ),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: dimColor.withValues(alpha: 0.06),
          child: Icon(
            Symbols.check_circle,
            // CircleAvatar wraps its child in MediaQuery.withNoTextScaling, so
            // the avatar is a fixed-size badge; size it with a plain constant
            // (matching GameAvatar's icon sizing) rather than a no-op scaler.
            size: 16 * 1.1,
            color: dimColor,
            fill: 1,
          ),
        ),
        title: Text(title, style: TextStyle(color: dimColor)),
      ),
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
      activeSessionProvider.select((a) {
        if (!a.hasMeaningfulPendingInput) return null;
        final p = a.pending;
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
        contentPadding: const EdgeInsetsDirectional.only(
          start: 16,
          end: 24,
          top: 6,
          bottom: 6,
        ),
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
          final state = ref.read(activeSessionProvider);
          // Pending game tile — resume directly.
          if (isPending) {
            ref.read(calculatorProvider.notifier).selectGame(game);
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RoundInputScreen()),
            );
            return;
          }
          // Other games are blocked while a pending game with meaningful input exists.
          if (state.hasMeaningfulPendingInput) {
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
    final (history, displayedPlayers, scoredAt, gameName) = ref.watch(
      activeSessionProvider.select(
        (a) => (a.history, a.displayedPlayers, a.scoredAt, a.gameName),
      ),
    );

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final roundsPlayed = history.length;
    final isFinished = roundsPlayed >= GameSession.totalRounds;

    // Sum scores per player in display order (shared primitive). Winners
    // (highest score, may be shared) are only highlighted once the game is
    // finished — mid-game leaders shouldn't claim the crown yet.
    final totals = cumulativeTotals(history, displayedPlayers);
    final winners = isFinished ? leaderIndices(totals) : const <int>[];

    // Muted tint for the trailing IconButtons, matching the home
    // session-card surface (standard 48dp tap targets).
    final mutedIconTheme = mutedIconButtonTheme(
      theme,
      foregroundColor: cs.onSurfaceVariant,
    );

    return Theme(
      data: mutedIconTheme,
      child: ScoreboardCard(
        roundsPlayed: roundsPlayed,
        playerNames: [for (final p in displayedPlayers) p.name],
        scores: totals,
        winners: winners,
        scoredAt: scoredAt,
        gameName: gameName,
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
  //   1. Snapshot the GameSession BEFORE the delete so the snackbar's
  //      undo can re-save it byte-for-byte.
  //   2. Capture the ScaffoldMessenger + root ProviderContainer BEFORE
  //      any await — both must outlive this widget, which is unmounted
  //      by the pop animation below.
  //   3. Delete from history, reset the calculator, then pop back to
  //      the existing HomeScreen (reuses it rather than a fresh one).
  //   4. Show the snackbar after the pop so it anchors to HomeScreen.
  Future<void> _deleteGame(BuildContext context, WidgetRef ref) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Spel verwijderen',
      contentText: 'Dit spel wordt permanent verwijderd uit de geschiedenis.',
      confirmLabel: 'Verwijderen',
      destructive: true,
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final session = ref.read(calculatorProvider.notifier).buildSession();
    final sessionId = ref.read(activeSessionProvider).sessionId;
    ref.read(calculatorProvider.notifier).cancelPendingAutosave();
    await ref.read(gameHistoryProvider.notifier).deleteGame(sessionId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (session != null) {
      showGameDeletedSnackBar(messenger, container, session);
    }
  }
}

class _NewGameSamePlayersButton extends ConsumerWidget {
  const _NewGameSamePlayersButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      icon: const Icon(Symbols.replay),
      label: const Text('Nieuw spel met dezelfde spelers'),
      onPressed: () => _onPressed(context, ref),
    );
  }

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    final state = ref.read(activeSessionProvider);
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
      activeSessionProvider.select(
        (a) => (a.history, a.displayedPlayers, a.hasPendingGame),
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
    final chooserIdx = seatIndexOf(players, record.chooserId);
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
                chooserIndex: chooserIdx,
              ),
              if (record.doubles.hasAnyDouble)
                DoublesChips(
                  doubles: record.doubles,
                  players: players,
                  chooserIndex: chooserIdx,
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
                      fullscreenDialog: true,
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
                    title: 'Ronde verwijderen',
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
          activeSessionProvider.select(
            (a) => (
              a.roundNumber,
              a.playerNames[a.dealerIndex],
              a.playerNames[(a.dealerIndex + 1) % playerCount],
              a.playerNames[a.starterIndex],
              a.history.length,
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

// =============================================================================
// Share card — dedicated widget rendered off-screen for image capture
// =============================================================================

class _ShareCard extends ConsumerWidget {
  const _ShareCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (history, displayedPlayers, scoredAt, gameName) = ref.watch(
      activeSessionProvider.select(
        (a) => (a.history, a.displayedPlayers, a.scoredAt, a.gameName),
      ),
    );

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final entries = rankScores(history, displayedPlayers);

    return Card(
      // Flat: the capture is a transparent PNG, so a drop shadow would paint
      // onto transparency as a grey halo. The surface colour follows the
      // current theme (dark mode → dark card) — intentional.
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    'assets/icon/icon_bonken_share.png',
                    width: 24,
                    height: 24,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Uitslag',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (gameName != null) ...[
              Text(
                gameName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatDate(scoredAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ] else
              Text(
                formatDate(scoredAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: IntrinsicColumnWidth(),
                2: IntrinsicColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (int i = 0; i < entries.length; i++)
                  TableRow(
                    decoration: entries[i].score == entries[0].score
                        ? BoxDecoration(
                            color: cs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 6,
                          end: 16,
                          top: 3,
                          bottom: 3,
                        ),
                        child: Text(
                          entries[i].name,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: 4,
                          top: 3,
                          bottom: 3,
                        ),
                        child: Text(
                          '${entries[i].score} pt',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scoreColor(entries[i].score, context),
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 4,
                          end: 6,
                          top: 3,
                          bottom: 3,
                        ),
                        child: entries[i].score == entries[0].score
                            ? Icon(
                                Symbols.emoji_events,
                                size: 16,
                                fill: 1,
                                color: cs.onTertiaryContainer,
                                semanticLabel: 'Winnaar',
                              )
                            : const SizedBox(width: 16),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
