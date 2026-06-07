// Tests for the game-selection body of [GameScreen]: which mini-game tiles
// are offered (negative / positive sections, played games filtered out), the
// per-chooser quota disabling + override dialog, pending-round blocking, and
// the finished-game state.
//
// The live-scoreboard header actions (Spel bewerken / Spel verwijderen) are
// covered by `game_screen_actions_test.dart`; this file focuses on the tile
// list and round flow.

import 'dart:async';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/game_catalog.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

RoundRecord _round(
  int n,
  MiniGame game,
  String chooserId,
  List<Player> players,
) => RoundRecord(
  roundNumber: n,
  game: game,
  chooserId: chooserId,
  scoresByPlayer: {for (final p in players) p.id: 0},
  input: game.inputDescriptor.defaults(players),
  doubles: const DoubleMatrix(),
);

GameSession _session({
  required List<Player> players,
  List<RoundRecord> rounds = const [],
  PendingRound? pendingRound,
  String? gameName,
}) => GameSession(
  id: 'seed',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  scoredAt: DateTime(2024),
  players: players,
  firstDealerId: players[0].id,
  rounds: rounds,
  pendingRound: pendingRound,
  gameName: gameName,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required GameSession session,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Tall surface so every game tile lays out — a ListView doesn't build
  // children far outside the default 800×600 viewport, which would hide the
  // positive-section tiles from the finders below.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await container.read(gameHistoryProvider.future);
  container.read(calculatorProvider.notifier).loadSession(session);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GameScreen()),
    ),
  );
  // Drain the autosave debounce scheduled by loadSession.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpPrefs();

  testWidgets('shows negative + positive sections with game tiles', (
    tester,
  ) async {
    final players = [for (final n in _names) Player(name: n)];
    await _pump(tester, session: _session(players: players));

    expect(find.text('Negatieve spellen'), findsOneWidget);
    expect(find.text('Positieve spellen'), findsOneWidget);
    expect(find.text('Bukken'), findsOneWidget); // Duck (negative)
    expect(find.text('Klaveren'), findsOneWidget); // Clubs (positive)
  });

  testWidgets('played games are filtered out of the tile list', (tester) async {
    final players = [for (final n in _names) Player(name: n)];
    final session = _session(
      players: players,
      rounds: [_round(1, const Duck(), players[1].id, players)],
    );
    await _pump(tester, session: session);

    // The Duck tile is gone; the history row ("Ronde 1 — Bukken") is a single
    // Text so it doesn't match the exact "Bukken" tile title.
    expect(find.text('Bukken'), findsNothing);
    expect(find.text('Klaveren'), findsOneWidget);
  });

  testWidgets('finished game (12 rounds) shows the replay button, no tiles', (
    tester,
  ) async {
    final players = [for (final n in _names) Player(name: n)];
    final rounds = [
      for (int i = 0; i < GameSession.totalRounds; i++)
        _round(i + 1, allGames[i], players[1].id, players),
    ];
    await _pump(
      tester,
      session: _session(players: players, rounds: rounds),
    );

    expect(find.text('Nieuw spel met dezelfde spelers'), findsOneWidget);
    expect(find.text('Negatieve spellen'), findsNothing);
    expect(find.text('Positieve spellen'), findsNothing);
  });

  group('share (finished game)', () {
    List<Player> mkPlayers() => [for (final n in _names) Player(name: n)];

    // 12 rounds so the game reads as finished. firstDealer = players[0] ⇒
    // display order is seat order, so per-player totals land in seat order.
    List<RoundRecord> finishedRounds(List<Player> players) => [
      for (int i = 0; i < GameSession.totalRounds; i++)
        _round(i + 1, allGames[i], players[1].id, players),
    ];

    test('rankScores: highest first, ties keep seat (display) order', () {
      final players = mkPlayers();
      final rounds = [
        RoundRecord(
          roundNumber: 1,
          game: const Duck(),
          chooserId: players[1].id,
          // Alice 10, Bob 30, Carol 30, Dan 0 — Bob/Carol tie at the top.
          scoresByPlayer: {
            players[0].id: 10,
            players[1].id: 30,
            players[2].id: 30,
            players[3].id: 0,
          },
          input: const Duck().inputDescriptor.defaults(players),
          doubles: const DoubleMatrix(),
        ),
      ];
      final session = _session(players: players, rounds: rounds);
      final ranked = rankScores(session.rounds, session.displayedPlayers);

      expect(
        [for (final e in ranked) e.name],
        ['Bob', 'Carol', 'Alice', 'Dan'],
      );
      // The 30-30 tie resolves to seat order (Bob seat 1 before Carol seat 2),
      // deterministically — not whatever order sort happens to leave.
      expect(ranked[0].seat, lessThan(ranked[1].seat));
    });

    test('buildShareText: header, name, date, trophy on the (tied) max', () {
      const entries = [
        (name: 'Bob', score: 30, seat: 1),
        (name: 'Carol', score: 30, seat: 2),
        (name: 'Alice', score: 10, seat: 0),
        (name: 'Dan', score: 0, seat: 3),
      ];
      final date = DateTime(2024, 6, 15);
      final lines = buildShareText(
        gameName: 'Kerst 2024',
        scoredAt: date,
        entries: entries,
      ).split('\n');

      expect(lines[0], 'Bonken uitslag');
      expect(lines[1], 'Kerst 2024');
      expect(lines[2], formatDate(date));
      // Both leaders get the trophy (ties shared); the rest do not.
      expect(lines[3], 'Bob  30 pt 🏆');
      expect(lines[4], 'Carol  30 pt 🏆');
      expect(lines[5], 'Alice  10 pt');
      expect(lines[6], 'Dan  0 pt');
    });

    test('buildShareText: omits the name line when gameName is null', () {
      const entries = [(name: 'Alice', score: 5, seat: 0)];
      // gameName omitted (defaults to null).
      final text = buildShareText(scoredAt: DateTime(2024), entries: entries);
      final lines = text.split('\n');
      // Date follows the header directly — no blank/`null` name line.
      expect(lines[1], formatDate(DateTime(2024)));
      expect(text, isNot(contains('null')));
    });

    testWidgets('share action is absent until the game is finished', (
      tester,
    ) async {
      final players = mkPlayers();
      await _pump(tester, session: _session(players: players));
      expect(find.byIcon(Symbols.share), findsNothing);
    });

    testWidgets('finished game shows the share action; long-press opens the '
        'format dialog', (tester) async {
      final players = mkPlayers();
      await _pump(
        tester,
        session: _session(
          players: players,
          rounds: finishedRounds(players),
          gameName: 'Kerst 2024',
        ),
      );
      expect(find.byIcon(Symbols.share), findsOneWidget);

      await tester.longPress(find.byIcon(Symbols.share));
      await tester.pumpAndSettle();

      // The popup dialog (not a menu) offers both formats plus a cancel action.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Afbeelding'), findsOneWidget);
      expect(find.text('Tekst'), findsOneWidget);
      expect(find.text('Annuleren'), findsOneWidget);
    });
  });

  testWidgets(
    'quota: chooser with 2 negatives → tile disabled, tap shows override dialog',
    (tester) async {
      final handle = tester.ensureSemantics();
      final players = [for (final n in _names) Player(name: n)];
      // firstDealer = players[0] + 2 completed rounds ⇒ current chooser is
      // players[3]. Attribute both negatives to players[3] so their negative
      // quota (max 2) is already full.
      final session = _session(
        players: players,
        rounds: [
          _round(1, const KingOfHearts(), players[3].id, players),
          _round(2, const KingsAndJacks(), players[3].id, players),
        ],
      );
      final container = await _pump(tester, session: session);
      expect(
        (container.read(calculatorProvider) as ActiveSession).chooserId,
        players[3].id,
      );

      await tester.ensureVisible(find.text('Vrouwen')); // Queens (negative)
      await tester.pumpAndSettle();

      // Quota-disabled tile must expose its override hint via the semantics
      // tree so screen readers can explain why the tile is dimmed.
      // MergeSemantics fuses our Semantics(button, hint) wrapper with the
      // inner ListTile (which contributes isFocusable, hasEnabledState,
      // isEnabled, hasSelectedState from its own semantics annotations).
      final quotaSemantics = tester.getSemantics(
        find
            .ancestor(
              of: find.widgetWithText(ListTile, 'Vrouwen'),
              matching: find.byType(MergeSemantics),
            )
            .last,
      );
      expect(
        quotaSemantics,
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          hint: 'Limiet bereikt; activeer om toch te kiezen',
        ),
      );

      await tester.tap(find.text('Vrouwen'));
      await tester.pumpAndSettle();

      expect(find.text('Limiet overschreden'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('pending round shows the hourglass tile and blocks other games', (
    tester,
  ) async {
    final players = [for (final n in _names) Player(name: n)];
    // Provide non-zero counts so hasMeaningfulPendingInput is true and the
    // hourglass + blocking behaviour activates.
    final input = CountsInput({
      players[0].id: 3,
      players[1].id: 0,
      players[2].id: 0,
      players[3].id: 0,
    });
    final session = _session(
      players: players,
      pendingRound: PendingRound(
        gameId: 'duck',
        gameName: 'Bukken',
        chooserId: players[1].id,
        input: input,
      ),
    );
    await _pump(tester, session: session);

    expect(find.byIcon(Symbols.hourglass_top), findsOneWidget);
    expect(find.textContaining('Niet afgerond'), findsOneWidget);

    // Tapping a different game is blocked by the "Ronde niet afgerond" dialog.
    await tester.ensureVisible(find.text('Klaveren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Klaveren'));
    await tester.pumpAndSettle();

    expect(find.text('Ronde niet afgerond'), findsOneWidget);
  });

  testWidgets(
    'show-played toggle is disabled for a category with nothing played',
    (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      await _pump(tester, session: _session(players: players));

      final toggles = find.widgetWithIcon(IconButton, Symbols.visibility);
      expect(toggles, findsNWidgets(2)); // one per section
      // Nothing played in either category → both disabled.
      expect(tester.widget<IconButton>(toggles.first).onPressed, isNull);
      expect(tester.widget<IconButton>(toggles.last).onPressed, isNull);
    },
  );

  testWidgets(
    'playing a negative enables its toggle and reveals the played tile',
    (tester) async {
      final handle = tester.ensureSemantics();
      final players = [for (final n in _names) Player(name: n)];
      final session = _session(
        players: players,
        rounds: [_round(1, const Duck(), players[1].id, players)],
      );
      await _pump(tester, session: session);

      // Negative toggle enabled (Duck played); positive toggle still disabled.
      final negToggle = find
          .widgetWithIcon(IconButton, Symbols.visibility)
          .first;
      final posToggle = find
          .widgetWithIcon(IconButton, Symbols.visibility)
          .last;
      expect(tester.widget<IconButton>(negToggle).onPressed, isNotNull);
      expect(tester.widget<IconButton>(posToggle).onPressed, isNull);

      // Played Duck is hidden by default, revealed after toggling.
      expect(find.text('Bukken'), findsNothing);
      await tester.tap(negToggle);
      await tester.pumpAndSettle();
      expect(find.text('Bukken'), findsOneWidget);
      expect(find.text('Spel al gespeeld'), findsOneWidget);

      // The revealed played-tile must expose its override hint via the
      // semantics tree so screen readers can explain the replay affordance.
      // MergeSemantics fuses our Semantics(button, hint) wrapper with the
      // inner ListTile (which contributes isFocusable, hasEnabledState,
      // isEnabled, hasSelectedState from its own semantics annotations).
      final playedSemantics = tester.getSemantics(
        find
            .ancestor(
              of: find.widgetWithText(ListTile, 'Bukken'),
              matching: find.byType(MergeSemantics),
            )
            .last,
      );
      expect(
        playedSemantics,
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          hint: 'Al gespeeld; activeer om opnieuw te spelen',
        ),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'tapping a revealed played game offers force-replay → navigates',
    (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      final session = _session(
        players: players,
        rounds: [_round(1, const Duck(), players[1].id, players)],
      );
      final container = await _pump(tester, session: session);

      await tester.tap(
        find.widgetWithIcon(IconButton, Symbols.visibility).first,
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Bukken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bukken'));
      await tester.pumpAndSettle();

      // Force-replay confirm dialog.
      expect(find.text('Toch spelen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Toch spelen'));
      await tester.pumpAndSettle();

      expect(find.byType(RoundInputScreen), findsOneWidget);
      expect(
        (container.read(calculatorProvider) as ActiveSession).selectedGame?.id,
        'duck',
      );

      // Drain the autosave debounce scheduled by selectGame.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'all games in a category played shows the all-played card; toggle reveals tiles',
    (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      final negatives = allGames
          .where((g) => g.category == GameCategory.negative)
          .toList();
      final rounds = [
        for (var i = 0; i < negatives.length; i++)
          _round(i + 1, negatives[i], players[1].id, players),
      ];
      await _pump(
        tester,
        session: _session(players: players, rounds: rounds),
      );

      // Negatives all played + toggle off: the all-played card fills the empty
      // section and no negative tiles render. Positives are untouched.
      expect(find.text('Alle negatieve spellen zijn gespeeld'), findsOneWidget);
      expect(find.text('Alle positieve spellen zijn gespeeld'), findsNothing);
      expect(find.text('Bukken'), findsNothing); // a negative tile, hidden
      expect(find.text('Klaveren'), findsOneWidget); // a positive tile, shown

      // Revealing the played negatives hides the card and renders the tiles.
      await tester.tap(
        find.widgetWithIcon(IconButton, Symbols.visibility).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Alle negatieve spellen zijn gespeeld'), findsNothing);
      await tester.ensureVisible(find.text('Bukken'));
      expect(find.text('Bukken'), findsOneWidget);
    },
  );

  testWidgets(
    'leaving via back-navigation flushes the autosave and resets to NoSession',
    (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gameHistoryProvider.future);
      container
          .read(calculatorProvider.notifier)
          .loadSession(_session(players: players));

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Center(child: Text('home'))),
          ),
        ),
      );
      // Drain the autosave debounce scheduled by loadSession.
      await tester.pump(const Duration(milliseconds: 500));

      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const GameScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);

      // Rename a player (schedules a debounced autosave), then leave before the
      // 400 ms debounce fires.
      container.read(calculatorProvider.notifier).setPlayerName(0, 'Zoë');
      await tester.pump();

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      // dispose() schedules flushAndReset via a post-frame callback; force one
      // more frame so it runs even if pumpAndSettle settled first.
      await tester.pump();

      // Back-navigation resets the calculator to the idle state…
      expect(container.read(calculatorProvider), isA<NoSession>());
      // …and the pre-debounce rename was flushed to history, not lost.
      final saved = container.read(gameHistoryProvider).value!;
      expect(saved.single.players.first.name, 'Zoë');
    },
  );
}
