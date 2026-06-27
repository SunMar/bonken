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
import 'package:bonken/models/rule_variants.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/round_input_screen.dart';
import 'package:bonken/services/io_failure.dart'
    show OutOfSpaceException, kOutOfSpaceMessage;
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/platform_io_providers.dart';
import 'package:bonken/utils.dart';
import 'package:bonken/widgets/share_result_card.dart'
    show buildShareText, rankScores;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  RuleVariants ruleVariants = const RuleVariants(),
}) => GameSession(
  id: kGameId1,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  scoredAt: DateTime(2024),
  players: players,
  firstDealerId: players[0].id,
  rounds: rounds,
  pendingRound: pendingRound,
  gameName: gameName,
  ruleVariants: ruleVariants,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required GameSession session,
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
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

/// Scrolls the game-selection body until the round-history card is on screen.
/// The history list sits below the (tall) game-tile sections, so the ListView
/// hasn't built it until it scrolls into view.
Future<void> _revealHistory(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Gespeelde rondes'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
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

  testWidgets(
    'history row pairs each name with its score in one semantics node',
    (tester) async {
      final handle = tester.ensureSemantics();
      final players = [for (final n in _names) Player(name: n)];
      final session = _session(
        players: players,
        rounds: [_round(1, const Duck(), players[1].id, players)],
      );
      await _pump(tester, session: session);
      await _revealHistory(tester);

      // Each player's name+score is announced together (not all four names then
      // all four scores); the visible "Alice:" / "0" texts are excluded.
      expect(find.bySemanticsLabel('Alice: 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Dan: 0'), findsOneWidget);
      handle.dispose();
    },
  );

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
    'replay button: pick a specific dealer → new game with same players and '
    'carried-over variants, back on the selection phase',
    (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      final rounds = [
        for (int i = 0; i < GameSession.totalRounds; i++)
          _round(i + 1, allGames[i], players[1].id, players),
      ];
      final container = await _pump(
        tester,
        session: _session(
          players: players,
          rounds: rounds,
          // A non-default variant that must survive the replay.
          ruleVariants: const RuleVariants(
            starterVariant: StarterVariant.oppositeChooserStarts,
          ),
        ),
      );

      await tester.tap(
        find.widgetWithText(FilledButton, 'Nieuw spel met dezelfde spelers'),
      );
      await tester.pumpAndSettle();

      // Pick Carol (seat 2) specifically — no announcement dialog on this path.
      // Scope to the dialog and take the last match (the player row, not the
      // "Volgende speler" subtitle).
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Carol'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      // Drain the autosave debounce scheduled by the new startNewGame.
      await tester.pump(const Duration(milliseconds: 500));

      final s = container.read(calculatorProvider) as ActiveSession;
      expect(s.playerNames, _names);
      expect(s.dealerIndex, 2); // Carol deals the first round
      expect(
        s.ruleVariants.starterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      // Back on a fresh selection phase: the game-tile sections reappear and
      // the replay button is gone.
      expect(find.text('Negatieve spellen'), findsOneWidget);
      expect(find.text('Nieuw spel met dezelfde spelers'), findsNothing);
    },
  );

  testWidgets('round-info banner derives chooser/dealer/starter + counter', (
    tester,
  ) async {
    final players = [for (final n in _names) Player(name: n)];
    // Two rounds played, firstDealer = Alice (seat 0) ⇒ round-3 dealer = Carol
    // (seat 2), chooser = Dan (dealer + 1 = seat 3). oppositeChooserStarts ⇒
    // starter = Bob (chooser − 2 = seat 1), so all three names are distinct.
    final session = _session(
      players: players,
      rounds: [
        _round(1, allGames[0], players[1].id, players),
        _round(2, allGames[1], players[2].id, players),
      ],
      ruleVariants: const RuleVariants(
        starterVariant: StarterVariant.oppositeChooserStarts,
      ),
    );
    await _pump(tester, session: session);

    expect(find.text('Ronde 3 van 12'), findsOneWidget);
    expect(find.textContaining('Kiezer: Dan'), findsOneWidget);
    expect(find.textContaining('Deler: Carol'), findsOneWidget);
    expect(find.textContaining('Uitkomst: Bob'), findsOneWidget);
  });

  testWidgets('round-info banner is hidden once the game is finished', (
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

    expect(find.textContaining('Kiezer:'), findsNothing);
    expect(find.textContaining(' van 12'), findsNothing);
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

    testWidgets('"Afbeelding" row exposes both "Delen" and "Opslaan" buttons', (
      tester,
    ) async {
      final players = mkPlayers();
      await _pump(
        tester,
        session: _session(players: players, rounds: finishedRounds(players)),
      );

      await tester.longPress(find.byIcon(Symbols.share));
      await tester.pumpAndSettle();

      final afbeeldingTile = find.ancestor(
        of: find.text('Afbeelding'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: afbeeldingTile,
          matching: find.byTooltip('Afbeelding delen'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: afbeeldingTile,
          matching: find.byTooltip('Afbeelding opslaan'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('explicit "Tekst" choice shares the result as text', (
      tester,
    ) async {
      final players = mkPlayers();
      String? sharedText;
      await _pump(
        tester,
        session: _session(
          players: players,
          rounds: finishedRounds(players),
          gameName: 'Kerst 2024',
        ),
        overrides: [
          shareTextProvider.overrideWithValue(({required text, subject}) async {
            sharedText = text;
          }),
        ],
      );

      await tester.longPress(find.byIcon(Symbols.share));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Tekst'),
            matching: find.byType(ListTile),
          ),
          matching: find.byTooltip('Tekst delen'),
        ),
      );
      await tester.pumpAndSettle();

      // The text payload reached the share provider (no platform involved)…
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Bonken uitslag'));
      expect(sharedText, contains('Kerst 2024'));
      // …and a successful share (or a cancellation) shows no error.
      expect(find.byType(SnackBar), findsNothing);
    });

    // Taps the long-press dialog's "Tekst delen" action.
    Future<void> tapShareText(WidgetTester tester) async {
      await tester.longPress(find.byIcon(Symbols.share));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Tekst'),
            matching: find.byType(ListTile),
          ),
          matching: find.byTooltip('Tekst delen'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('text share that throws → generic failure snackbar', (
      tester,
    ) async {
      final players = mkPlayers();
      await _pump(
        tester,
        session: _session(players: players, rounds: finishedRounds(players)),
        overrides: [
          // A generic (bug / platform) failure → the generic message.
          shareTextProvider.overrideWithValue(
            ({required text, subject}) async => throw Exception('share boom'),
          ),
        ],
      );

      await tapShareText(tester);

      expect(
        find.text('Het is mislukt om de uitslag te delen.'),
        findsOneWidget,
      );

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    });

    testWidgets('text share out of space → actionable storage snackbar', (
      tester,
    ) async {
      final players = mkPlayers();
      await _pump(
        tester,
        session: _session(players: players, rounds: finishedRounds(players)),
        overrides: [
          // The service surfaces a full disk as OutOfSpaceException → the
          // user-fixable message rather than the generic one.
          shareTextProvider.overrideWithValue(
            ({required text, subject}) async =>
                throw const OutOfSpaceException(),
          ),
        ],
      );

      await tapShareText(tester);

      expect(find.text(kOutOfSpaceMessage), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    });

    testWidgets('"Tekst kopiëren" copies the result to the clipboard', (
      tester,
    ) async {
      final players = mkPlayers();
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(
        tester,
        session: _session(
          players: players,
          rounds: finishedRounds(players),
          gameName: 'Kerst 2024',
        ),
      );

      await tester.longPress(find.byIcon(Symbols.share));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Tekst'),
            matching: find.byType(ListTile),
          ),
          matching: find.byTooltip('Tekst kopiëren'),
        ),
      );
      await tester.pumpAndSettle();

      // The payload reached the clipboard (no platform involved) and the user
      // got confirmation.
      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Bonken uitslag'));
      expect(clipboardText, contains('Kerst 2024'));
      expect(find.text('Tekst gekopieerd naar klembord'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5)); // drain snackbar
    });

    testWidgets('plain tap shares directly — it never opens the format dialog', (
      tester,
    ) async {
      final players = mkPlayers();
      await _pump(
        tester,
        session: _session(players: players, rounds: finishedRounds(players)),
      );

      // A plain tap fires the default share (onPressed), NOT the format dialog
      // — only a long-press / the screen-reader actions open that. The
      // through-capture image→text path itself stays out of widget tests: its
      // real async (asset precache + RepaintBoundary→PNG) is non-deterministic
      // under the test binding (see the note below). runAsync lets the precache
      // resolve so nothing dangles at teardown.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Symbols.share));
      });
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('share button exposes the four screen-reader format actions', (
      tester,
    ) async {
      final players = mkPlayers();
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        session: _session(players: players, rounds: finishedRounds(players)),
      );

      // The long-press lives on IconButton.onLongPress; the four custom actions
      // must still fold onto the single share-button node.
      expect(
        tester.getSemantics(find.byIcon(Symbols.share)),
        isSemantics(
          isButton: true,
          customActions: const [
            CustomSemanticsAction(label: 'Deel als afbeelding'),
            CustomSemanticsAction(label: 'Deel als tekst'),
            CustomSemanticsAction(label: 'Bewaar als afbeelding'),
            CustomSemanticsAction(label: 'Kopieer als tekst'),
          ],
        ),
      );
      handle.dispose();
    });

    testWidgets('share format dialog: Annuleren closes it without sharing', (
      tester,
    ) async {
      final players = mkPlayers();
      var shareCalls = 0;
      await _pump(
        tester,
        session: _session(players: players, rounds: finishedRounds(players)),
        overrides: [
          shareTextProvider.overrideWithValue(({required text, subject}) async {
            shareCalls++;
          }),
        ],
      );

      await tester.longPress(find.byIcon(Symbols.share));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(shareCalls, 0);
    });

    // The image paths (_shareImage, _saveImage) are intentionally not
    // widget-tested: reaching their share/save call requires _captureShareCard's
    // real RepaintBoundary→PNG capture, which is non-deterministic under the
    // test binding. Both route through the platform_io_providers seam
    // (shareFileProvider / saveImageFileProvider) and their boolean/error
    // handling mirrors the export paths covered by export_screen_test.dart;
    // adding a capture seam purely for tests would reintroduce the very smell
    // this change removes.
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

      // Hold a subscription so Riverpod's autoDispose microtask (fired when
      // container.read() closes its temporary sub) cannot dispose
      // calculatorProvider before GameScreen subscribes via ref.watch().
      final navKeepAlive = container.listen<CalculatorState>(
        calculatorProvider,
        (_, _) {},
      );
      container
          .read(calculatorProvider.notifier)
          .loadSession(_session(players: players));
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const GameScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // GameScreen is now subscribed — release the keepAlive so that
      // back-navigation later can trigger autoDispose normally.
      navKeepAlive.close();
      expect(find.byType(GameScreen), findsOneWidget);

      // Rename a player (schedules a debounced autosave), then leave before the
      // 400 ms debounce fires.
      container.read(calculatorProvider.notifier).setPlayerName(0, 'Zoë');
      await tester.pump();

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      // autoDispose fires once all listeners drop; onDispose writes the save
      // asynchronously. One extra pump fires that timer and lets the write complete.
      await tester.pump();

      // Back-navigation resets the calculator to the idle state…
      expect(container.read(calculatorProvider), isA<NoSession>());
      // …and the pre-debounce rename was flushed to history, not lost.
      final saved = container.read(gameHistoryProvider).value!;
      expect(saved.single.players.first.name, 'Zoë');
    },
  );

  group('live scoreboard winner-gating', () {
    RoundRecord leadRound(
      List<Player> players,
      MiniGame game,
      int roundNumber,
    ) => RoundRecord(
      roundNumber: roundNumber,
      game: game,
      chooserId: players[1].id,
      // Alice clearly ahead; everyone else flat.
      scoresByPlayer: {
        players[0].id: 30,
        players[1].id: 0,
        players[2].id: 0,
        players[3].id: 0,
      },
      input: game.inputDescriptor.defaults(players),
      doubles: const DoubleMatrix(),
    );

    testWidgets('mid-game: the leader is not crowned', (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      // One round in — unfinished, so no trophy even though Alice leads.
      await _pump(
        tester,
        session: _session(
          players: players,
          rounds: [leadRound(players, const Duck(), 1)],
        ),
      );

      expect(find.byIcon(Symbols.emoji_events), findsNothing);
    });

    testWidgets('finished: only the sole leader is crowned', (tester) async {
      final players = [for (final n in _names) Player(name: n)];
      // 12 rounds → finished. Alice scores 30 in round 1, everyone 0 elsewhere,
      // so the cumulative totals are [30, 0, 0, 0] — Alice is the unique leader.
      final rounds = [
        leadRound(players, allGames[0], 1),
        for (int i = 1; i < GameSession.totalRounds; i++)
          _round(i + 1, allGames[i], players[1].id, players),
      ];
      await _pump(
        tester,
        session: _session(players: players, rounds: rounds),
      );

      expect(find.byIcon(Symbols.emoji_events), findsOneWidget);
    });
  });

  group('history row interactions', () {
    List<Player> mkPlayers() => [for (final n in _names) Player(name: n)];

    testWidgets('only the last round shows delete; confirming removes it', (
      tester,
    ) async {
      final players = mkPlayers();
      final session = _session(
        players: players,
        rounds: [
          _round(1, allGames[0], players[1].id, players),
          _round(2, allGames[1], players[2].id, players),
        ],
      );
      final container = await _pump(tester, session: session);
      expect(
        (container.read(calculatorProvider) as ActiveSession).history.length,
        2,
      );

      await _revealHistory(tester);

      // Two rounds → two edit buttons, exactly one delete (on the last round).
      expect(find.byTooltip('Wijzigen'), findsNWidgets(2));
      expect(find.byTooltip('Ronde verwijderen'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Ronde verwijderen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ronde verwijderen'));
      await tester.pumpAndSettle();

      // The confirm dialog names round 2 — the most recent — not round 1,
      // proving the button targets the last round it was rendered against.
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Ronde 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Ronde 1')),
        findsNothing,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Verwijderen'));
      await tester.pumpAndSettle();

      final s = container.read(calculatorProvider) as ActiveSession;
      expect(s.history.length, 1);
      expect(s.history.single.roundNumber, 1);

      await tester.pump(const Duration(milliseconds: 500)); // drain autosave
      await tester.pumpAndSettle();
    });

    testWidgets('no delete button while a pending round is present', (
      tester,
    ) async {
      final players = mkPlayers();
      final played = allGames.firstWhere((g) => g.id != 'duck');
      final input = CountsInput({
        players[0].id: 3,
        players[1].id: 0,
        players[2].id: 0,
        players[3].id: 0,
      });
      final session = _session(
        players: players,
        rounds: [_round(1, played, players[1].id, players)],
        pendingRound: PendingRound(
          gameId: 'duck',
          chooserId: players[1].id,
          input: input,
        ),
      );
      await _pump(tester, session: session);

      await _revealHistory(tester);

      // The one completed round still offers edit…
      expect(find.byTooltip('Wijzigen'), findsOneWidget);
      // …but delete is gated off while a pending round exists (!hasPendingGame).
      expect(find.byTooltip('Ronde verwijderen'), findsNothing);
    });

    testWidgets('tapping "Wijzigen" opens the round edit screen', (
      tester,
    ) async {
      final players = mkPlayers();
      final session = _session(
        players: players,
        rounds: [
          _round(1, allGames[0], players[1].id, players),
          _round(2, allGames[1], players[2].id, players),
        ],
      );
      await _pump(tester, session: session);

      await _revealHistory(tester);
      await tester.ensureVisible(find.byTooltip('Wijzigen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Wijzigen').first);
      await tester.pumpAndSettle();

      expect(find.byType(RoundInputScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500)); // drain autosave
      await tester.pumpAndSettle();
    });
  });
}
