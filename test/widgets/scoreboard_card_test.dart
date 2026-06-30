import 'package:bonken/models/game_session.dart';
import 'package:bonken/utils.dart';
import 'package:bonken/widgets/scoreboard_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '_helpers.dart';

void main() {
  group('ScoreboardCard', () {
    final testDate = DateTime(2024, 6, 15);

    testWidgets(
      'mid-game state: progress glyph, no trophy, no winner highlight',
      (tester) async {
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: 5,
            playerNames: playerNames,
            scores: const [10, 30, 20, 0],
            winners: const [],
            scoredAt: testDate,
          ),
        );

        // Mid-game: must NOT show the finished glyph or a trophy chip.
        expect(find.byIcon(Symbols.check_circle), findsNothing);
        expect(find.byIcon(Symbols.emoji_events), findsNothing);
        // 5/12 = ~42% → clock_loader_40 (the 30..50% bucket).
        expect(find.byIcon(Symbols.clock_loader_40), findsOneWidget);
        // Header date rendered, scores rendered with formatScore signs.
        expect(find.text(formatDate(testDate)), findsOneWidget);
        expect(find.text('+10'), findsOneWidget);
        expect(find.text('+30'), findsOneWidget);
        expect(find.text('+20'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      },
    );

    testWidgets(
      'finished single-winner state: filled check + one trophy on the winning chip',
      (tester) async {
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: GameSession.totalRounds,
            playerNames: playerNames,
            scores: const [40, 100, 30, -10],
            winners: const [1],
            scoredAt: testDate,
          ),
        );

        expect(find.byIcon(Symbols.check_circle), findsOneWidget);
        // Exactly one trophy — winner index 1 only.
        expect(find.byIcon(Symbols.emoji_events), findsOneWidget);
        expect(find.text(formatDate(testDate)), findsOneWidget);
        expect(find.text('-10'), findsOneWidget);
      },
    );

    testWidgets('tied final: two trophies for two winners', (tester) async {
      await pumpHost(
        tester,
        ScoreboardCard(
          roundsPlayed: GameSession.totalRounds,
          playerNames: playerNames,
          scores: const [50, 50, 30, 20],
          winners: const [0, 1],
          scoredAt: testDate,
        ),
      );

      expect(find.byIcon(Symbols.emoji_events), findsNWidgets(2));
    });

    testWidgets('gameName set: name is primary header, date is subtitle', (
      tester,
    ) async {
      await pumpHost(
        tester,
        ScoreboardCard(
          roundsPlayed: 3,
          playerNames: playerNames,
          scores: const [0, 0, 0, 0],
          winners: const [],
          scoredAt: testDate,
          gameName: 'Kerst 2024',
        ),
      );

      expect(find.text('Kerst 2024'), findsOneWidget);
      expect(find.text(formatDate(testDate)), findsOneWidget);

      // Role check, not just presence: the name is the bold primary header …
      final cs = Theme.of(tester.element(find.text('Kerst 2024'))).colorScheme;
      final nameText = tester.widget<Text>(find.text('Kerst 2024'));
      expect(nameText.style?.fontWeight, FontWeight.bold);
      // … and the date is the muted, non-bold subtitle beneath it.
      final dateText = tester.widget<Text>(find.text(formatDate(testDate)));
      expect(dateText.style?.fontWeight, isNot(FontWeight.bold));
      expect(dateText.style?.color, cs.onSurfaceVariant);
    });

    testWidgets('gameName null: the date becomes the bold primary header', (
      tester,
    ) async {
      await pumpHost(
        tester,
        ScoreboardCard(
          roundsPlayed: 3,
          playerNames: playerNames,
          scores: const [0, 0, 0, 0],
          winners: const [],
          scoredAt: testDate,
        ),
      );

      expect(find.text(formatDate(testDate)), findsOneWidget);
      // With no name, the date takes over the primary header role (bold), rather
      // than rendering as the muted subtitle it is when a name is present.
      final dateText = tester.widget<Text>(find.text(formatDate(testDate)));
      expect(dateText.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('tappable card exposes button role and semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        ScoreboardCard(
          roundsPlayed: 2,
          playerNames: playerNames,
          scores: const [0, 0, 0, 0],
          winners: const [],
          scoredAt: testDate,
          onTap: () {},
          tapSemanticLabel: 'Open spel',
        ),
      );
      // The InkWell inside ScoreboardCard internally uses FocusableActionDetector
      // which creates a MergeSemantics boundary. The outer
      // Semantics(button: true, label: tapSemanticLabel) annotation is
      // inherited into this boundary node. The chip-level MergeSemantics nodes
      // appear deeper in the tree (inside ExcludeSemantics); .first gives us
      // the outermost node — exercises the a11y API (not just the widget
      // hierarchy) by asserting on the merged semantics data.
      final semantics = tester.getSemantics(
        find
            .descendant(
              of: find.byType(ScoreboardCard),
              matching: find.byType(MergeSemantics),
            )
            .first,
      );
      expect(
        semantics,
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'Open spel',
        ),
      );
      handle.dispose();
    });

    testWidgets(
      'onTap == null: no InkWell wired up; non-null: InkWell present and fires',
      (tester) async {
        // Non-tappable variant.
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: 2,
            playerNames: playerNames,
            scores: const [0, 0, 0, 0],
            winners: const [],
            scoredAt: testDate,
          ),
        );
        expect(find.byType(InkWell), findsNothing);

        // Tappable variant.
        var taps = 0;
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: 2,
            playerNames: playerNames,
            scores: const [0, 0, 0, 0],
            winners: const [],
            scoredAt: testDate,
            onTap: () => taps++,
          ),
        );
        expect(find.byType(InkWell), findsOneWidget);
        await tester.tap(find.byType(InkWell));
        expect(taps, 1);
      },
    );

    testWidgets(
      'tappable card: a tap on the decorative title opens the card (regression)',
      (tester) async {
        // The title Text sits over the full-card InkWell. A glyph-bearing Text
        // absorbs the hit, so unless the InkWell is its *ancestor* the tap is
        // swallowed and the card never opens. Tap the title itself (not the safe
        // chip/padding area, which masked this) to lock the behaviour in.
        var taps = 0;
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: 4,
            playerNames: playerNames,
            scores: const [0, 0, 0, 0],
            winners: const [],
            scoredAt: testDate,
            gameName: 'Avondje bonken',
            onTap: () => taps++,
            tapSemanticLabel: 'Open spel',
          ),
        );

        await tester.tap(find.text('Avondje bonken'));
        expect(taps, 1, reason: 'tapping the title must open the card');
      },
    );

    testWidgets(
      'tappable card: the trailing button fires its own action, not the card',
      (tester) async {
        // The overlaid trailing button must win its own taps without also
        // triggering the card's onTap — otherwise the Home delete button would
        // open the game it is trying to delete.
        var cardTaps = 0;
        var deletes = 0;
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: 4,
            playerNames: playerNames,
            scores: const [0, 0, 0, 0],
            winners: const [],
            scoredAt: testDate,
            gameName: 'Avondje bonken',
            onTap: () => cardTaps++,
            tapSemanticLabel: 'Open spel',
            headerTrailing: IconButton(
              icon: const Icon(Symbols.delete),
              tooltip: 'Verwijderen',
              onPressed: () => deletes++,
            ),
          ),
        );

        await tester.tap(find.byIcon(Symbols.delete));
        expect(deletes, 1, reason: 'the trailing button handles its own tap');
        expect(cardTaps, 0, reason: 'and does not also open the card');
      },
    );

    testWidgets(
      'tappable card: headerTrailing action stays reachable to assistive tech',
      (tester) async {
        // Regression: when the card is tappable AND carries a trailing action
        // (the Home delete button), the action must not be swallowed by the
        // card's MergeSemantics/ExcludeSemantics — it has to stay a separately
        // reachable node, or screen-reader/switch users lose the only delete.
        final handle = tester.ensureSemantics();
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: 2,
            playerNames: playerNames,
            scores: const [0, 0, 0, 0],
            winners: const [],
            scoredAt: testDate,
            onTap: () {},
            tapSemanticLabel: 'Open spel',
            headerTrailing: IconButton(
              icon: const Icon(Symbols.delete),
              tooltip: 'Verwijderen',
              onPressed: () {},
            ),
          ),
        );
        // The trailing delete button is reachable as its own button node — its
        // own tooltip proves it wasn't merged into the card's "Open spel" node
        // (the regression returned that node instead, with no 'Verwijderen').
        expect(
          tester.getSemantics(find.byTooltip('Verwijderen')),
          isSemantics(isButton: true, isEnabled: true, tooltip: 'Verwijderen'),
        );
        // ...alongside the still-reachable card-open button.
        expect(find.bySemanticsLabel('Open spel'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('headerTrailing: rendered when non-null, absent when null', (
      tester,
    ) async {
      await pumpHost(
        tester,
        ScoreboardCard(
          roundsPlayed: 0,
          playerNames: playerNames,
          scores: const [0, 0, 0, 0],
          winners: const [],
          scoredAt: testDate,
        ),
      );
      expect(find.byIcon(Symbols.delete), findsNothing);

      await pumpHost(
        tester,
        ScoreboardCard(
          roundsPlayed: 0,
          playerNames: playerNames,
          scores: const [0, 0, 0, 0],
          winners: const [],
          scoredAt: testDate,
          headerTrailing: IconButton(
            icon: const Icon(Symbols.delete),
            onPressed: () {},
          ),
        ),
      );
      expect(find.byIcon(Symbols.delete), findsOneWidget);
    });

    // Threshold table for the in-progress glyph. Each entry picks one
    // rounds-played value inside its bucket and asserts the matching
    // `clock_loader_*` frame renders. The finished state (which uses
    // `check_circle` instead) is covered by its own test above.
    const buckets = <(int rounds, IconData glyph)>[
      (0, Symbols.clock_loader_10), //  0/12 =  0% → <15%
      (1, Symbols.clock_loader_10), //  1/12 =  8% → <15%
      (2, Symbols.clock_loader_20), //  2/12 = 17% → <30%
      (3, Symbols.clock_loader_20), //  3/12 = 25% → <30%
      (4, Symbols.clock_loader_40), //  4/12 = 33% → <50%
      (5, Symbols.clock_loader_40), //  5/12 = 42% → <50%
      (6, Symbols.clock_loader_60), //  6/12 = 50% → <70%
      (7, Symbols.clock_loader_60), //  7/12 = 58% → <70%
      (8, Symbols.clock_loader_60), //  8/12 = 67% → <70%
      (9, Symbols.clock_loader_80), //  9/12 = 75% → <90%
      (10, Symbols.clock_loader_80), // 10/12 = 83% → <90%
      (11, Symbols.clock_loader_90), // 11/12 = 92% → ≥90%
    ];
    for (final (rounds, glyph) in buckets) {
      testWidgets('progress glyph: $rounds rounds → $glyph', (tester) async {
        await pumpHost(
          tester,
          ScoreboardCard(
            roundsPlayed: rounds,
            playerNames: playerNames,
            scores: const [0, 0, 0, 0],
            winners: const [],
            scoredAt: testDate,
          ),
        );
        expect(find.byIcon(glyph), findsOneWidget);
        // Sanity: the finished glyph never appears in mid-game states.
        expect(find.byIcon(Symbols.check_circle), findsNothing);
      });
    }
  });
}
