import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

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
///
/// Pass [starterVariantOverride] / [heartsVariantOverride] to lock the
/// variant displayed (used when rules are opened from within a game). When
/// both are null the widget reads the app-wide default providers.
/// When an override is present, variant-sensitive blocks show only the active
/// text — the "Spelregel variant" alternative note is hidden (the player is
/// committed to one rule set for their session).
class RulesBlockView extends ConsumerWidget {
  const RulesBlockView({
    super.key,
    required this.block,
    this.starterVariantOverride,
    this.heartsVariantOverride,
  });

  final Block block;

  /// When non-null, overrides the app default for starter-variant display.
  final StarterVariant? starterVariantOverride;

  /// When non-null, overrides the app default for hearts-variant display.
  final HeartsVariant? heartsVariantOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    // Resolve both variants before the switch. The override wins when set;
    // otherwise the app-wide default provider is used.
    final StarterVariant resolvedStarter =
        starterVariantOverride ?? ref.watch(defaultStarterVariantProvider);
    final HeartsVariant resolvedHearts =
        heartsVariantOverride ?? ref.watch(defaultHeartsVariantProvider);
    return switch (block) {
      final Para b => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(
          _parseInline(b.text, tt.bodyMedium ?? const TextStyle()),
          style: tt.bodyMedium,
        ),
      ),
      final RichPara b => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(
          TextSpan(
            style: tt.bodyMedium,
            children: [
              for (final span in b.spans)
                switch (span) {
                  final InlineText s => _parseInline(
                    s.text,
                    tt.bodyMedium ?? const TextStyle(),
                  ),
                  final InlineIcon s => WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(s.icon, size: 14, color: tt.bodyMedium?.color),
                  ),
                },
            ],
          ),
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
                      switch (b.items[i]) {
                        final String s => _parseInline(
                          s,
                          tt.bodyMedium ?? const TextStyle(),
                        ),
                        final VariantBlock v => TextSpan(
                          children: [
                            TextSpan(
                              text: v.textFor(switch (v.variantKind) {
                                VariantKind.starter => resolvedStarter,
                                VariantKind.hearts => resolvedHearts,
                              }),
                            ),
                            if (switch (v.variantKind) {
                              VariantKind.starter =>
                                starterVariantOverride == null,
                              VariantKind.hearts =>
                                heartsVariantOverride == null,
                            })
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: _SettingsIconButton(
                                  variantKind: v.variantKind,
                                  resolvedVariant: switch (v.variantKind) {
                                    VariantKind.starter => resolvedStarter,
                                    VariantKind.hearts => resolvedHearts,
                                  },
                                ),
                              ),
                          ],
                        ),
                        _ => throw StateError(
                          'Unexpected NumberedList item: ${b.items[i].runtimeType}',
                        ),
                      },
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
      final VariantBlock b => _VariantBlockView(
        block: b,
        resolvedVariant: switch (b.variantKind) {
          VariantKind.starter => resolvedStarter,
          VariantKind.hearts => resolvedHearts,
        },
        hasOverride: switch (b.variantKind) {
          VariantKind.starter => starterVariantOverride != null,
          VariantKind.hearts => heartsVariantOverride != null,
        },
      ),
    };
  }
}

class _VariantBlockView extends StatelessWidget {
  const _VariantBlockView({
    required this.block,
    required this.resolvedVariant,
    required this.hasOverride,
  });

  final VariantBlock block;
  final Enum resolvedVariant;

  /// When true the tune icon is hidden (in-game scope: variant is fixed).
  final bool hasOverride;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final String text = block.textFor(resolvedVariant);
    final tuneIcon = hasOverride
        ? null
        : _SettingsIconButton(
            variantKind: block.variantKind,
            resolvedVariant: resolvedVariant,
          );
    return block.label != null
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 2),
            child: _NoteCallout(
              label: block.label!,
              text: text,
              trailing: tuneIcon,
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(child: Text(text, style: tt.bodyMedium)),
                ?tuneIcon,
              ],
            ),
          );
  }
}

/// Material 3 highlighted callout used to render [Note] and labeled
/// [VariantBlock] blocks. When [trailing] is provided the label is rendered on
/// its own row alongside the widget (e.g. a tune icon), followed by [text] on
/// the next line. Without [trailing] the label and text are rendered inline.
class _NoteCallout extends StatelessWidget {
  const _NoteCallout({required this.label, required this.text, this.trailing});

  final String label;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final decoration = BoxDecoration(
      color: cs.surfaceContainerHighest,
      border: Border(left: BorderSide(color: cs.primary, width: 3)),
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(4),
        bottomRight: Radius.circular(4),
      ),
    );
    if (trailing != null) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$label:',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                trailing!,
              ],
            ),
            Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
          ],
        ),
      );
    }
    return Container(
      decoration: decoration,
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

class _SettingsIconButton extends StatelessWidget {
  const _SettingsIconButton({
    required this.variantKind,
    required this.resolvedVariant,
  });

  final VariantKind variantKind;
  final Enum resolvedVariant;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.settings),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      tooltip: 'Spelregel variant',
      onPressed: () => unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => _VariantDialog(
            variantKind: variantKind,
            initialVariant: resolvedVariant,
          ),
        ),
      ),
    );
  }
}

class _VariantDialog extends ConsumerStatefulWidget {
  const _VariantDialog({
    required this.variantKind,
    required this.initialVariant,
  });

  final VariantKind variantKind;
  final Enum initialVariant;

  @override
  ConsumerState<_VariantDialog> createState() => _VariantDialogState();
}

class _VariantDialogState extends ConsumerState<_VariantDialog> {
  late Enum _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.initialVariant;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spelregel variant'),
      content: SingleChildScrollView(
        child: switch (widget.variantKind) {
          VariantKind.starter => RadioGroup<StarterVariant>(
            groupValue: _pending as StarterVariant,
            onChanged: (v) {
              if (v != null) setState(() => _pending = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in StarterVariant.values)
                  RadioListTile<StarterVariant>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.label),
                    subtitle: Text(v.description),
                    value: v,
                  ),
              ],
            ),
          ),
          VariantKind.hearts => RadioGroup<HeartsVariant>(
            groupValue: _pending as HeartsVariant,
            onChanged: (v) {
              if (v != null) setState(() => _pending = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in HeartsVariant.values)
                  RadioListTile<HeartsVariant>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.label),
                    subtitle: Text(v.description),
                    value: v,
                  ),
              ],
            ),
          ),
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        FilledButton(onPressed: _save, child: const Text('Opslaan')),
      ],
    );
  }

  void _save() {
    switch (widget.variantKind) {
      case VariantKind.starter:
        unawaited(
          ref
              .read(defaultStarterVariantProvider.notifier)
              .setVariant(_pending as StarterVariant),
        );
      case VariantKind.hearts:
        unawaited(
          ref
              .read(defaultHeartsVariantProvider.notifier)
              .setVariant(_pending as HeartsVariant),
        );
    }
    Navigator.of(context).pop();
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
