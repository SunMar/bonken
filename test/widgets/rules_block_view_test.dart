import 'package:bonken/data/game_rules.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
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

Future<void> _pump(
  WidgetTester tester,
  Block block, {
  StarterVariant? starterOverride,
  HeartsVariant? heartsOverride,
  StarterVariant defaultStarter = StarterVariant.dealerStarts,
  HeartsVariant defaultHearts = HeartsVariant.onlyAfterPlayedHeart,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        defaultStarterVariantProvider.overrideWith(
          () => DefaultStarterVariantNotifier(initialVariant: defaultStarter),
        ),
        defaultHeartsVariantProvider.overrideWith(
          () => DefaultHeartsVariantNotifier(initialVariant: defaultHearts),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RulesBlockView(
              block: block,
              starterVariantOverride: starterOverride,
              heartsVariantOverride: heartsOverride,
            ),
          ),
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
}
