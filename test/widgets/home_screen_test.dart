// Tests for [HomeScreen]: the empty placeholder, the saved-games list,
// resuming a session by tapping its card, the card delete + undo flow, and the
// unsupported-storage-version screen.

import 'package:bonken/models/double_matrix.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/games/negative_games.dart';
import 'package:bonken/models/input_descriptor.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/models/round_record.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/home_screen.dart';
import 'package:bonken/screens/new_game_screen.dart';
import 'package:bonken/state/calculator_provider.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/storage_exceptions.dart';
import 'package:bonken/widgets/app_bar_widgets.dart';
import 'package:bonken/widgets/scoreboard_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const _names = ['Alice', 'Bob', 'Carol', 'Dan'];

GameSession _session(String id) {
  final players = [for (final n in _names) Player(name: n)];
  return GameSession(
    id: id,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: players,
    firstDealerId: players[0].id,
    rounds: [
      RoundRecord(
        roundNumber: 1,
        game: const Dominoes(),
        chooserId: players[1].id,
        scoresByPlayer: {
          players[0].id: -100,
          players[1].id: 0,
          players[2].id: 0,
          players[3].id: 0,
        },
        input: RecipientInput([players[0].id]),
        doubles: const DoubleMatrix(),
      ),
    ],
  );
}

/// A finished (12-round) session in which Alice is the sole leader, for
/// exercising the card's "Afgerond spel" label and winner highlight.
///
/// Every round is a valid Dominoes round (its totalPoints, −100, lands on the
/// recipient). Spreading the loss across Bob/Carol/Dan — never Alice — keeps
/// Alice at 0, the unique leader, while each round still sums to totalPoints so
/// it survives `saveGame`'s validation.
GameSession _finishedSession(String id) {
  final players = [for (final n in _names) Player(name: n)];
  RoundRecord dominoesRound(int n, Player recipient) => RoundRecord(
    roundNumber: n,
    game: const Dominoes(),
    chooserId: players[1].id,
    scoresByPlayer: {
      for (final p in players) p.id: p.id == recipient.id ? -100 : 0,
    },
    input: RecipientInput([recipient.id]),
    doubles: const DoubleMatrix(),
  );
  return GameSession(
    id: id,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: players,
    firstDealerId: players[0].id,
    rounds: [
      // Cycle the loss through Bob (seat 1), Carol (2), Dan (3) — 4 each.
      for (int i = 0; i < GameSession.totalRounds; i++)
        dominoesRound(i + 1, players[1 + (i % 3)]),
    ],
  );
}

/// Pumps [HomeScreen] in [container], seeding [saved] sessions first.
Future<void> _pumpHome(
  WidgetTester tester,
  ProviderContainer container, {
  List<GameSession> saved = const [],
}) async {
  await container.read(gameHistoryProvider.future);
  for (final s in saved) {
    await container.read(gameHistoryProvider.notifier).saveGame(s);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps [HomeScreen] with [settingsLoadErrorProvider] seeded to [error] (so the
/// settings-error branch renders), optionally seeding [saved] game sessions
/// first to prove the settings reset leaves history untouched.
Future<ProviderContainer> _pumpHomeSettingsError(
  WidgetTester tester, {
  required Object error,
  List<GameSession> saved = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsLoadErrorProvider.overrideWith(
        () => SettingsLoadErrorNotifier(
          initialError: (error, StackTrace.current),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(gameHistoryProvider.future);
  for (final s in saved) {
    await container.read(gameHistoryProvider.notifier).saveGame(s);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Mocks the `url_launcher` platform channel so the error-report `mailto:`
/// launch can be exercised without a real platform. Returns the list of URLs
/// the app asked to launch; [result] is what the platform reports back (true =
/// a mail app handled it, false = none available). The handler is removed on
/// teardown.
List<String> _mockUrlLauncher(WidgetTester tester, {required bool result}) {
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    switch (call.method) {
      case 'canLaunch':
        return true;
      case 'launch':
      case 'launchUrl':
        launched.add((call.arguments as Map)['url'] as String);
        return result;
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return launched;
}

void main() {
  setUpPrefs();

  testWidgets('shows the placeholder when there are no saved games', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container);

    expect(find.text('Nog geen gespeelde spellen'), findsOneWidget);
  });

  testWidgets('renders a card per saved session under the "Spellen" header', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_session(kGameId1)]);

    expect(find.text('Spellen'), findsOneWidget);
    expect(find.byType(ScoreboardCard), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets(
    'multiple sessions render one card each under a single "Spellen" header',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpHome(
        tester,
        container,
        saved: [_session(kGameId1), _session(kGameId2), _session(kGameId3)],
      );

      expect(find.byType(ScoreboardCard), findsNWidgets(3));
      // The header is rendered once, not per card.
      expect(find.text('Spellen'), findsOneWidget);
      expect(find.text('Nog geen gespeelde spellen'), findsNothing);
    },
  );

  testWidgets(
    'running session: "Lopend spel … ronde N van 12" label, no winner',
    (tester) async {
      final handle = tester.ensureSemantics();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The fixture session has one round played → running, "ronde 2 van 12".
      await _pumpHome(tester, container, saved: [_session(kGameId1)]);

      expect(
        find.bySemanticsLabel(RegExp('Lopend spel.*ronde 2 van 12')),
        findsOneWidget,
      );
      // Mid-game leaders aren't crowned, so no trophy on the card.
      expect(find.byIcon(Symbols.emoji_events), findsNothing);
      handle.dispose();
    },
  );

  testWidgets('finished session: "Afgerond spel" label, leader crowned', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_finishedSession(kGameId1)]);

    expect(find.bySemanticsLabel(RegExp('Afgerond spel')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Lopend spel')), findsNothing);
    // Finished: the sole leader (Alice, +100) is highlighted with the trophy.
    expect(find.byIcon(Symbols.emoji_events), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a card loads the session and opens the GameScreen', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_session(kGameId1)]);

    await tester.tap(find.byType(ScoreboardCard));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(
      (container.read(calculatorProvider) as ActiveSession).sessionId,
      kGameId1,
    );

    // Drain the autosave debounce scheduled by loadSession.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('deleting a card removes it; snackbar undo restores it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpHome(tester, container, saved: [_session(kGameId1)]);

    await tester.tap(find.byTooltip('Verwijderen'));
    await tester.pumpAndSettle();

    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == kGameId1),
      isFalse,
    );
    expect(find.text('Het spel is verwijderd.'), findsOneWidget);
    expect(find.text('Ongedaan maken'), findsOneWidget);

    // Invoke the undo action directly (tapping it also hides the snackbar,
    // which would race the belt-and-suspenders close Timer).
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    action.onPressed();
    await tester.pump();
    expect(
      container.read(gameHistoryProvider).value?.any((g) => g.id == kGameId1),
      isTrue,
    );

    // Drain the snackbar auto-dismiss Timer + exit animation.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('unsupported storage version shows the update screen', (
    tester,
  ) async {
    setAsyncPrefs({'game_history': '{"version":99,"games":[]}'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Let build() reject into AsyncError before the ~200ms Riverpod retry.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('App bijwerken vereist'), findsOneWidget);
    expect(find.text('Geschiedenis wissen'), findsOneWidget);

    // Drain the retry: remove the bad key so the retried build() returns []
    // cleanly, then let the single pending timer fire.
    final prefs = SharedPreferencesAsync();
    await prefs.remove('game_history');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('corrupt storage shows the corrupt-data screen', (tester) async {
    setAsyncPrefs({'bonken_game_history': 'this is not json'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Geschiedenis beschadigd'), findsOneWidget);
    expect(find.text('Geschiedenis wissen'), findsOneWidget);

    // Drain the retry (same pattern as the unsupported-version test).
    final prefs = SharedPreferencesAsync();
    await prefs.remove('bonken_game_history');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('corrupt storage screen shows Verstuur foutrapport button', (
    tester,
  ) async {
    setAsyncPrefs({'bonken_game_history': 'this is not json'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Verstuur foutrapport'), findsOneWidget);

    final prefs = SharedPreferencesAsync();
    await prefs.remove('bonken_game_history');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'unsupported version screen does not show Verstuur foutrapport button',
    (tester) async {
      setAsyncPrefs({'game_history': '{"version":99,"games":[]}'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Verstuur foutrapport'), findsNothing);

      final prefs = SharedPreferencesAsync();
      await prefs.remove('game_history');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('tapping Verstuur foutrapport button shows confirmation dialog', (
    tester,
  ) async {
    setAsyncPrefs({'bonken_game_history': 'this is not json'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Verstuur foutrapport'));
    await tester.pumpAndSettle();

    // Confirm dialog appears.
    expect(find.text('Versturen'), findsOneWidget);

    // Dismiss by cancelling — avoids hitting url_launcher in tests.
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    final prefs = SharedPreferencesAsync();
    await prefs.remove('bonken_game_history');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  // The error-report launch flow is shared by both storage-error screens; drive
  // it through the SETTINGS-error path, which seeds the error via a provider
  // override (no game-history retry timer to drain) — keeping the launch
  // assertions deterministic.
  testWidgets(
    'error report: confirming with a mail app launches a mailto: and no fallback',
    (tester) async {
      final launched = _mockUrlLauncher(tester, result: true);
      await _pumpHomeSettingsError(
        tester,
        error: const CorruptPersistenceException('bad'),
      );

      await tester.tap(find.text('Verstuur foutrapport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versturen'));
      await tester.pumpAndSettle();

      // A mail app handled it → a mailto: was launched and no fallback shows.
      expect(launched.single, startsWith('mailto:support@suninet.org'));
      expect(find.text('Kan e-mail niet openen'), findsNothing);
    },
  );

  testWidgets(
    'error report: no mail app shows the "Kan e-mail niet openen" fallback',
    (tester) async {
      _mockUrlLauncher(tester, result: false);
      await _pumpHomeSettingsError(
        tester,
        error: const CorruptPersistenceException('bad'),
      );

      await tester.tap(find.text('Verstuur foutrapport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versturen'));
      await tester.pumpAndSettle();

      expect(find.text('Kan e-mail niet openen'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'history error keeps the app-bar write actions (settings still load)',
    (tester) async {
      setAsyncPrefs({'bonken_game_history': 'this is not json'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Geschiedenis beschadigd'), findsOneWidget);
      // Settings are fine on a history error, so the theme menu + settings
      // button stay available (the opposite of the settings-error screen).
      expect(find.byType(SettingsIconButton), findsOneWidget);
      expect(find.byType(ThemeMenuButton), findsOneWidget);

      final prefs = SharedPreferencesAsync();
      await prefs.remove('bonken_game_history');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'history error: "Geschiedenis wissen" clears history and recovers',
    (tester) async {
      setAsyncPrefs({'bonken_game_history': 'this is not json'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Geschiedenis beschadigd'), findsOneWidget);

      await tester.tap(find.text('Geschiedenis wissen'));
      await tester.pumpAndSettle();
      // The history reset is destructive (permanent delete) — its confirm copy
      // distinguishes it from the non-destructive settings reset.
      expect(
        find.text(
          'Alle gespeelde spellen worden permanent verwijderd. '
          'Dit kan niet ongedaan worden gemaakt.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Wissen'));
      await tester.pumpAndSettle();

      // Recovered: the error screen is gone and the empty home shows.
      expect(find.text('Geschiedenis beschadigd'), findsNothing);
      expect(find.text('Nog geen gespeelde spellen'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('"Nieuw spel" opens the NewGameScreen once history has loaded', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Empty (but loaded) history → hasValue is true → the bottom button shows.
    await _pumpHome(tester, container);

    expect(find.text('Nieuw spel'), findsOneWidget);
    await tester.tap(find.text('Nieuw spel'));
    await tester.pumpAndSettle();

    expect(find.byType(NewGameScreen), findsOneWidget);
  });

  group('settings storage-error screen', () {
    testWidgets(
      'corrupt settings: title + report + clear button, and the app-bar write '
      'actions are stripped',
      (tester) async {
        await _pumpHomeSettingsError(
          tester,
          error: const CorruptPersistenceException('bad'),
        );

        expect(find.text('Instellingen beschadigd'), findsOneWidget);
        expect(find.text('Verstuur foutrapport'), findsOneWidget);
        expect(find.text('Instellingen wissen'), findsOneWidget);

        // The theme menu + settings screen write through the settings blob —
        // the very thing that failed to load — so they're hidden here (like
        // MigrationScreen), leaving only the inert About button + plain title.
        expect(find.byType(SettingsIconButton), findsNothing);
        expect(find.byType(ThemeMenuButton), findsNothing);
        expect(find.byType(TitleWithRules), findsNothing);
        expect(find.byType(AboutIconButton), findsOneWidget);

        // The error view replaces the whole scaffold → no "Nieuw spel" action.
        expect(find.text('Nieuw spel'), findsNothing);
      },
    );

    testWidgets('unsupported settings version: title + no report button', (
      tester,
    ) async {
      await _pumpHomeSettingsError(
        tester,
        error: const UnsupportedVersionException(99),
      );

      expect(find.text('App bijwerken vereist'), findsOneWidget);
      // Report button is gated off for the unsupported-version kind.
      expect(find.text('Verstuur foutrapport'), findsNothing);
      expect(find.text('Instellingen wissen'), findsOneWidget);
    });

    testWidgets(
      '"Instellingen wissen" resets settings (non-destructive) and leaves '
      'history untouched',
      (tester) async {
        final seed = SharedPreferencesAsync();
        await seed.setString(
          settingsStorageKey,
          '{"version":1,"corrupt":true}',
        );

        final container = await _pumpHomeSettingsError(
          tester,
          error: const CorruptPersistenceException('bad'),
          saved: [_session(kGameId1)],
        );

        await tester.tap(find.text('Instellingen wissen'));
        await tester.pumpAndSettle();
        // Non-destructive reset copy (distinct from the destructive history
        // "permanent verwijderd" wording) — pins the right descriptor.
        expect(
          find.text(
            'Je instellingen worden teruggezet naar de standaardwaarden.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Wissen'));
        await tester.pumpAndSettle();

        // clearSettings removed the stored blob...
        final prefs = SharedPreferencesAsync();
        expect(await prefs.getString(settingsStorageKey), isNull);
        // ...the error cleared (normal home is back)...
        expect(find.text('Instellingen beschadigd'), findsNothing);
        // ...and the settings reset never touched game history.
        expect(
          container
              .read(gameHistoryProvider)
              .value
              ?.any((g) => g.id == kGameId1),
          isTrue,
        );
      },
    );
  });

  group('buildDebugReport', () {
    final when = DateTime(2024, 1, 2, 3, 4, 5);

    test('caps an oversized raw-storage blob with a marker', () {
      final huge = 'x' * 5000;
      final report = buildDebugReport(null, null, huge, when);

      expect(report, contains('=== Raw storage data ==='));
      expect(report, contains('x' * 3000)); // head kept (cap is 3000)
      expect(report, isNot(contains('x' * 3001))); // …and nothing past it
      expect(report, contains('ingekort: 2000 tekens')); // 5000 − 3000 dropped
    });

    test('caps an oversized stack trace with a marker', () {
      final trace = StackTrace.fromString('frame\n' * 1000); // 6000 chars
      final report = buildDebugReport(null, trace, null, when);

      expect(report, contains('=== Stack trace ==='));
      expect(report, contains('ingekort:'));
    });

    test('leaves a small raw-storage blob intact', () {
      const small = '{"version":7,"games":[]}';
      final report = buildDebugReport(null, null, small, when);

      expect(report, contains(small));
      expect(report, isNot(contains('ingekort:')));
    });

    test('includes the CorruptPersistenceException cause', () {
      final report = buildDebugReport(
        const CorruptPersistenceException('dangling player id'),
        null,
        null,
        when,
      );

      expect(report, contains('=== Cause ==='));
      expect(report, contains('dangling player id'));
    });
  });
}
