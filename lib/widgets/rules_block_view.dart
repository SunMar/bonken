import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_rules.dart';
import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';

/// Renders a single [Block] from [game_rules.dart] as Material widgets.
///
/// This is the canonical Flutter renderer for the structured rules data and
/// is shared between the full rules screen and the per-game rules screen.
/// Anything visual about how a block looks lives here, not in the data.
class RulesBlockView extends ConsumerWidget {
  const RulesBlockView({super.key, required this.block});

  final Block block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    return switch (block) {
      final Para b => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(
          _parseInline(b.text, tt.bodyMedium ?? const TextStyle()),
          style: tt.bodyMedium,
        ),
      ),
      final BulletList b => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in b.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '•  '),
                      _parseInline(item, tt.bodyMedium ?? const TextStyle()),
                    ],
                  ),
                  style: tt.bodyMedium,
                ),
              ),
          ],
        ),
      ),
      final NumberedList b => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < b.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${b.startFrom + i}.  '),
                      _parseInline(
                        b.items[i],
                        tt.bodyMedium ?? const TextStyle(),
                      ),
                    ],
                  ),
                  style: tt.bodyMedium,
                ),
              ),
          ],
        ),
      ),
      final TableBlock b => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _RulesTable(block: b),
      ),
      final Note b => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 2),
        child: _NoteCallout(label: b.label, text: b.text),
      ),
      final StarterVariantBlock b => _StarterVariantBlockView(
        block: b,
        ref: ref,
      ),
      final HeartsVariantNote b => _HeartsVariantNoteView(block: b, ref: ref),
    };
  }
}

class _StarterVariantBlockView extends StatelessWidget {
  const _StarterVariantBlockView({required this.block, required this.ref});

  final StarterVariantBlock block;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final variant = ref.watch(defaultStarterVariantProvider);
    final activeText = variant == StarterVariant.dealerStarts
        ? block.dealerStartsText
        : block.oppositeChooserStartsText;
    final alternativeText = variant == StarterVariant.dealerStarts
        ? block.oppositeChooserStartsText
        : block.dealerStartsText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2, left: 4),
          child: Text(
            '${block.stepNumber}.  $activeText',
            style: tt.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: _NoteCallout(
            label: 'Spelregel variant',
            text: alternativeText,
          ),
        ),
      ],
    );
  }
}

class _HeartsVariantNoteView extends StatelessWidget {
  const _HeartsVariantNoteView({required this.block, required this.ref});

  final HeartsVariantNote block;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final variant = ref.watch(defaultHeartsVariantProvider);
    final activeText = variant == HeartsVariant.onlyAfterPlayedHeart
        ? block.onlyAfterPlayedHeartText
        : block.graduatedUnlockText;
    final alternativeText = variant == HeartsVariant.onlyAfterPlayedHeart
        ? block.graduatedUnlockText
        : block.onlyAfterPlayedHeartText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 2),
          child: _NoteCallout(label: block.label, text: activeText),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _NoteCallout(
            label: 'Spelregel variant',
            text: alternativeText,
          ),
        ),
      ],
    );
  }
}

/// Material 3 highlighted callout used to render [Note] blocks.
///
/// Uses the theme's `surfaceContainerHighest` for a subtle raised tint
/// against the surrounding rules text, with a `primary` left bar and bold
/// label to flag that the content is a sidenote worth pausing on.  Stays
/// in lock-step with the seed colour and dark-mode palette automatically.
class _NoteCallout extends StatelessWidget {
  const _NoteCallout({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
      child: Text.rich(
        TextSpan(
          style: tt.bodyMedium?.copyWith(color: cs.onSurface),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

class _RulesTable extends StatelessWidget {
  const _RulesTable({required this.block});

  final TableBlock block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final headerStyle = tt.labelMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: cs.onSurfaceVariant,
    );
    final cellStyle = tt.bodySmall;

    Alignment alignFor(int col) => block.alignRight.contains(col)
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(color: cs.outlineVariant),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outline, width: 1.2)),
            ),
            children: [
              for (int c = 0; c < block.headers.length; c++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Align(
                    alignment: alignFor(c),
                    child: Text(block.headers[c], style: headerStyle),
                  ),
                ),
            ],
          ),
          for (final row in block.rows)
            TableRow(
              children: [
                for (int c = 0; c < row.length; c++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Align(
                      alignment: alignFor(c),
                      child: Text(row[c], style: cellStyle),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Tiny `**bold**` parser → [TextSpan].
TextSpan _parseInline(String text, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*');
  int cursor = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    spans.add(
      TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: baseStyle, children: spans);
}
