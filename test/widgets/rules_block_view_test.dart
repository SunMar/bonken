import 'package:bonken/data/game_rules.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
import 'package:bonken/state/rules_locked_provider.dart';
import 'package:bonken/widgets/rules_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../test_helpers.dart';

const _starterBlock = VariantBlock(
  variantKind: VariantKind.starter,
  texts: {
    StarterVariant.dealerStarts: 'De deler komt uit.',
    StarterVariant.oppositeChooserStarts: 'Tegenover de kiezer komt uit.',
  },
);

const _heartsBlock = VariantBlock(
  variantKind: VariantKind.hearts,
  label: 'Extra spelregel',
  texts: {
    HeartsVariant.onlyAfterPlayedHeart: 'Alleen na bijgespeelde harten.',
    HeartsVariant.graduatedUnlock: 'Gefaseerde opening tekst.',
  },
);

/// Pumps [block] in a [RulesBlockView]. A non-null [starterOverride] /
/// [heartsOverride] mirrors the in-game scope: it both fixes the displayed
/// variant (via the default-variant provider) and locks the rules
/// ([rulesLockedProvider] → true) so the settings icon / alternative is hidden.
/// [defaultStarter] / [defaultHearts] set the unlocked app-default values.
Future<void> _pump(
  WidgetTester tester,
  Block block, {
  StarterVariant? starterOverride,
  HeartsVariant? heartsOverride,
  StarterVariant defaultStarter = StarterVariant.dealerStarts,
  HeartsVariant defaultHearts = HeartsVariant.onlyAfterPlayedHeart,
}) async {
  final bool locked = starterOverride != null || heartsOverride != null;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        defaultStarterVariantProvider.overrideWith(
          () => DefaultStarterVariantNotifier(
            initialVariant: starterOverride ?? defaultStarter,
          ),
        ),
        defaultHeartsVariantProvider.overrideWith(
          () => DefaultHeartsVariantNotifier(
            initialVariant: heartsOverride ?? defaultHearts,
          ),
        ),
        rulesLockedProvider.overrideWithValue(locked),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RulesBlockView(block: block)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpPrefs();
  initializeWidgets();

  // -----------------------------------------------------------------------
  // VariantBlock starter — active text and settings icon
  // -----------------------------------------------------------------------
  group('VariantBlock starter — active text', () {
    testWidgets('shows active text (dealerStarts by default)', (tester) async {
      await _pump(tester, _starterBlock);
      expect(find.textContaining('De deler komt uit.'), findsOneWidget);
    });

    testWidgets('switches active text when provider changes', (tester) async {
      await _pump(
        tester,
        _starterBlock,
        defaultStarter: StarterVariant.oppositeChooserStarts,
      );
      expect(
        find.textContaining('Tegenover de kiezer komt uit.'),
        findsOneWidget,
      );
    });

    testWidgets('shows active text for the overridden variant', (tester) async {
      await _pump(
        tester,
        _starterBlock,
        starterOverride: StarterVariant.oppositeChooserStarts,
      );
      expect(
        find.textContaining('Tegenover de kiezer komt uit.'),
        findsOneWidget,
      );
    });

    testWidgets('shows settings icon when no override', (tester) async {
      await _pump(tester, _starterBlock);
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });

    testWidgets('hides settings icon when override is set', (tester) async {
      await _pump(
        tester,
        _starterBlock,
        starterOverride: StarterVariant.dealerStarts,
      );
      expect(find.byIcon(Symbols.settings), findsNothing);
    });

    testWidgets('tapping settings icon opens variant dialog', (tester) async {
      await _pump(tester, _starterBlock);
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pumpAndSettle();
      expect(find.text('Spelregel variant'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // VariantBlock hearts — active labeled callout and settings icon
  // -----------------------------------------------------------------------
  group('VariantBlock hearts — active labeled callout', () {
    testWidgets('shows active text (onlyAfterPlayedHeart by default)', (
      tester,
    ) async {
      await _pump(tester, _heartsBlock);
      expect(
        find.textContaining('Alleen na bijgespeelde harten.'),
        findsOneWidget,
      );
    });

    testWidgets('shows active text for the overridden variant', (tester) async {
      await _pump(
        tester,
        _heartsBlock,
        heartsOverride: HeartsVariant.graduatedUnlock,
      );
      expect(find.textContaining('Gefaseerde opening tekst.'), findsOneWidget);
    });

    testWidgets('shows settings icon when no override', (tester) async {
      await _pump(tester, _heartsBlock);
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });

    testWidgets('hides settings icon when override is set', (tester) async {
      await _pump(
        tester,
        _heartsBlock,
        heartsOverride: HeartsVariant.graduatedUnlock,
      );
      expect(find.byIcon(Symbols.settings), findsNothing);
    });

    testWidgets('tapping settings icon opens variant dialog', (tester) async {
      await _pump(tester, _heartsBlock);
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pumpAndSettle();
      expect(find.text('Spelregel variant'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // VariantBlock nested as a NumberedList step (VariantItem)
  // -----------------------------------------------------------------------
  group('NumberedList with an inline VariantItem', () {
    const numbered = NumberedList([
      TextItem('Eerste stap.'),
      VariantItem(_starterBlock),
      TextItem('Laatste stap.'),
    ]);

    testWidgets('renders plain steps and the active variant step', (
      tester,
    ) async {
      await _pump(tester, numbered);
      expect(find.textContaining('Eerste stap.'), findsOneWidget);
      expect(find.textContaining('De deler komt uit.'), findsOneWidget);
      expect(find.textContaining('Laatste stap.'), findsOneWidget);
    });

    testWidgets('uses the active variant text when the provider changes', (
      tester,
    ) async {
      await _pump(
        tester,
        numbered,
        defaultStarter: StarterVariant.oppositeChooserStarts,
      );
      expect(
        find.textContaining('Tegenover de kiezer komt uit.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the settings icon when unlocked', (tester) async {
      await _pump(tester, numbered);
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });

    testWidgets('hides the settings icon when locked', (tester) async {
      await _pump(
        tester,
        numbered,
        starterOverride: StarterVariant.dealerStarts,
      );
      expect(find.byIcon(Symbols.settings), findsNothing);
    });
  });

  // -----------------------------------------------------------------------
  // RichPara — inline text plus an inline icon
  // -----------------------------------------------------------------------
  group('RichPara', () {
    testWidgets('renders inline text and the inline icon', (tester) async {
      await _pump(
        tester,
        const RichPara([
          InlineText('Voor '),
          InlineIcon(Symbols.settings),
          InlineText(' na'),
        ]),
      );
      expect(find.textContaining('Voor'), findsOneWidget);
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // Variant dialog save flow (standalone / unlocked page)
  // -----------------------------------------------------------------------
  group('variant dialog save', () {
    testWidgets('picking a variant and saving updates the shown rule', (
      tester,
    ) async {
      await _pump(tester, _starterBlock);
      expect(find.textContaining('De deler komt uit.'), findsOneWidget);

      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      // Dialog closed and the block now reflects the saved variant.
      expect(find.text('Spelregel variant'), findsNothing);
      expect(
        find.textContaining('Tegenover de kiezer komt uit.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling leaves the variant unchanged', (tester) async {
      await _pump(tester, _starterBlock);
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StarterVariant.oppositeChooserStarts.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();

      expect(find.text('Spelregel variant'), findsNothing);
      expect(find.textContaining('De deler komt uit.'), findsOneWidget);
    });
  });
}
