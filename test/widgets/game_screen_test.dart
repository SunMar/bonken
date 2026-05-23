// Tests for the game-selection body of [GameScreen]: which mini-game tiles
// are offered (negative / positive sections, played games filtered out), the
// per-chooser quota disabling + override dialog, pending-round blocking, and
// the finished-game state.
//
// The live-scoreboard header actions (Spel bewerken / Spel verwijderen) are
// covered by `game_screen_actions_test.dart`; this file focuses on the tile
// list and round flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/game_catalog.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/mini_game.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';

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
  input: const {},
  doubles: const DoubleMatrix(),
);

GameSession _session({
  required List<Player> players,
  List<RoundRecord> rounds = const [],
  PendingRound? pendingRound,
}) => GameSession(
  id: 'seed',
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
  players: players,
  firstDealerId: players[0].id,
  rounds: rounds,
  pendingRound: pendingRound,
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

  testWidgets(
    'quota: chooser with 2 negatives → tile disabled, tap shows override dialog',
    (tester) async {
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
      expect(container.read(calculatorProvider).chooserId, players[3].id);

      await tester.ensureVisible(find.text('Vrouwen')); // Queens (negative)
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vrouwen'));
      await tester.pumpAndSettle();

      expect(find.text('Limiet overschreden'), findsOneWidget);
    },
  );

  testWidgets('pending round shows the hourglass tile and blocks other games', (
    tester,
  ) async {
    final players = [for (final n in _names) Player(name: n)];
    final session = _session(
      players: players,
      pendingRound: PendingRound(
        gameId: 'duck',
        gameName: 'Bukken',
        chooserId: players[1].id,
        input: const {},
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
      expect(container.read(calculatorProvider).selectedGame?.id, 'duck');

      // Drain the autosave debounce scheduled by selectGame.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    },
  );
}
