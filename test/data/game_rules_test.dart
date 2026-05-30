import 'package:bonken/data/game_rules.dart';
import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every variant-dependent rule block, gathered from the whole document —
/// both top-level [VariantBlock]s and the ones nested as [VariantItem] steps
/// inside a [NumberedList].
Iterable<VariantBlock> _variantBlocksIn(List<Block> blocks) sync* {
  for (final Block b in blocks) {
    if (b is VariantBlock) yield b;
    if (b is NumberedList) {
      for (final NumberedItem item in b.items) {
        if (item is VariantItem) yield item.block;
      }
    }
  }
}

Set<Enum> _enumValuesFor(VariantKind kind) => switch (kind) {
  VariantKind.starter => StarterVariant.values.toSet(),
  VariantKind.hearts => HeartsVariant.values.toSet(),
};

void main() {
  test('every VariantBlock.texts covers exactly its kind\'s enum values', () {
    final List<Block> allBlocks = [
      for (final Section s in kSectionsBeforeGames) ...s.blocks,
      ...kNegatieveIntroSection.blocks,
      ...kPositieveIntroSection.blocks,
      for (final GameSection g in kGameSections) ...g.blocks,
      for (final Section s in kSectionsAfterGames) ...s.blocks,
    ];

    final List<VariantBlock> variantBlocks = _variantBlocksIn(
      allBlocks,
    ).toList();

    // Sanity: the document actually contains variant blocks of both kinds, so
    // a future refactor that drops them doesn't make this test vacuously pass.
    expect(variantBlocks, isNotEmpty);
    expect(variantBlocks.map((b) => b.variantKind).toSet(), {
      VariantKind.starter,
      VariantKind.hearts,
    });

    for (final VariantBlock vb in variantBlocks) {
      expect(
        vb.texts.keys.toSet(),
        equals(_enumValuesFor(vb.variantKind)),
        reason:
            'VariantBlock(${vb.variantKind}) must map every variant value to '
            'rule text so textFor() can never miss.',
      );
    }
  });
}
