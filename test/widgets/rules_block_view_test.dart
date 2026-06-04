import 'package:bonken/data/game_rules.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
import 'package:bonken/state/rules_edit_mode_provider.dart';
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

const _starterLabeledBlock = VariantBlock(
  variantKind: VariantKind.starter,
  label: 'Spelregel',
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

/// Pumps [block] in a [RulesBlockView].
///
/// [starterOverride] / [heartsOverride] fix the displayed variant via the
/// default-variant providers. [editMode] is forwarded to [rulesEditModeProvider]
/// to control how the cog icon behaves. [defaultStarter] / [defaultHearts] set
/// the app-default values when no override is supplied.
Future<void> _pump(
  WidgetTester tester,
  Block block, {
  StarterVariant? starterOverride,
  HeartsVariant? heartsOverride,
  StarterVariant defaultStarter = StarterVariant.dealerStarts,
  HeartsVariant defaultHearts = HeartsVariant.onlyAfterPlayedHeart,
  RulesEditMode editMode = RulesEditMode.enabled,
}) async {
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
        rulesEditModeProvider.overrideWithValue(editMode),
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

    testWidgets('hides settings icon when hidden', (tester) async {
      await _pump(
        tester,
        _starterBlock,
        starterOverride: StarterVariant.dealerStarts,
        editMode: RulesEditMode.hidden,
      );
      expect(find.byIcon(Symbols.settings), findsNothing);
    });

    testWidgets('shows settings icon when disabled', (tester) async {
      await _pump(
        tester,
        _starterBlock,
        starterOverride: StarterVariant.dealerStarts,
        editMode: RulesEditMode.disabled,
      );
      expect(find.byIcon(Symbols.settings), findsOneWidget);
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

    testWidgets('hides settings icon when hidden', (tester) async {
      await _pump(
        tester,
        _heartsBlock,
        heartsOverride: HeartsVariant.graduatedUnlock,
        editMode: RulesEditMode.hidden,
      );
      expect(find.byIcon(Symbols.settings), findsNothing);
    });

    testWidgets('shows settings icon when disabled', (tester) async {
      await _pump(
        tester,
        _heartsBlock,
        heartsOverride: HeartsVariant.graduatedUnlock,
        editMode: RulesEditMode.disabled,
      );
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });

    testWidgets('tapping settings icon opens variant dialog', (tester) async {
      await _pump(tester, _heartsBlock);
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pumpAndSettle();
      expect(find.text('Spelregel variant'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // VariantBlock starter — active labeled callout and settings icon
  // -----------------------------------------------------------------------
  group('VariantBlock starter — active labeled callout', () {
    testWidgets('shows active text (dealerStarts by default)', (tester) async {
      await _pump(tester, _starterLabeledBlock);
      expect(find.textContaining('De deler komt uit.'), findsOneWidget);
    });

    testWidgets('shows active text for the overridden variant', (tester) async {
      await _pump(
        tester,
        _starterLabeledBlock,
        starterOverride: StarterVariant.oppositeChooserStarts,
      );
      expect(
        find.textContaining('Tegenover de kiezer komt uit.'),
        findsOneWidget,
      );
    });

    testWidgets('shows settings icon when no override', (tester) async {
      await _pump(tester, _starterLabeledBlock);
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });

    testWidgets('hides settings icon when hidden', (tester) async {
      await _pump(
        tester,
        _starterLabeledBlock,
        starterOverride: StarterVariant.dealerStarts,
        editMode: RulesEditMode.hidden,
      );
      expect(find.byIcon(Symbols.settings), findsNothing);
    });

    testWidgets('shows settings icon when disabled', (tester) async {
      await _pump(
        tester,
        _starterLabeledBlock,
        starterOverride: StarterVariant.dealerStarts,
        editMode: RulesEditMode.disabled,
      );
      expect(find.byIcon(Symbols.settings), findsOneWidget);
    });

    testWidgets('tapping settings icon opens variant dialog', (tester) async {
      await _pump(tester, _starterLabeledBlock);
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pumpAndSettle();
      expect(find.text('Spelregel variant'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // disabled — cog shown, tapping shows snackbar (not dialog)
  // -----------------------------------------------------------------------
  group('disabled cog behaviour', () {
    testWidgets('tapping settings icon shows snackbar, not dialog', (
      tester,
    ) async {
      await _pump(
        tester,
        _starterBlock,
        starterOverride: StarterVariant.dealerStarts,
        editMode: RulesEditMode.disabled,
      );
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pump();
      expect(find.text('Spelregel variant'), findsNothing);
      expect(find.textContaining('Spel bewerken'), findsOneWidget);
      // Drain the showTimedSnackBar internal timer before the test ends.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('tapping settings icon in labeled callout shows snackbar', (
      tester,
    ) async {
      await _pump(
        tester,
        _starterLabeledBlock,
        starterOverride: StarterVariant.dealerStarts,
        editMode: RulesEditMode.disabled,
      );
      await tester.tap(find.byIcon(Symbols.settings));
      await tester.pump();
      expect(find.text('Spelregel variant'), findsNothing);
      expect(find.textContaining('Spel bewerken'), findsOneWidget);
      // Drain the showTimedSnackBar internal timer before the test ends.
      await tester.pumpAndSettle(const Duration(seconds: 5));
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

    testWidgets(
      'never shows a settings icon (variant control is in the callout)',
      (tester) async {
        await _pump(tester, numbered);
        expect(find.byIcon(Symbols.settings), findsNothing);
      },
    );
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
