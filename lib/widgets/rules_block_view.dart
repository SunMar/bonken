import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/game_rules.dart';
import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/rules_edit_mode_provider.dart';
import '../utils.dart';
import 'incomplete_form_snackbar.dart';
import 'variant_radio_list.dart';

/// Renders a single [Block] from [game_rules.dart] as Material widgets.
///
/// This is the canonical Flutter renderer for the structured rules data and
/// is shared between the full rules screen and the per-game rules screen.
/// Anything visual about how a block looks lives here, not in the data.
///
/// The active variant for each kind comes from the default-variant providers,
/// and [rulesEditModeProvider] decides whether variant-sensitive blocks expose
/// the settings icon and "Spelregel variant" alternative. `RulesIconButton`
/// overrides both (scoped to the pushed route) when rules are opened from
/// within a game, so the player sees only their committed rule set.
class RulesBlockView extends ConsumerWidget {
  const RulesBlockView({super.key, required this.block});

  final Block block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final StarterVariant resolvedStarter = ref.watch(
      defaultStarterVariantProvider,
    );
    final HeartsVariant resolvedHearts = ref.watch(
      defaultHeartsVariantProvider,
    );
    final RulesEditMode editMode = ref.watch(rulesEditModeProvider);
    // Resolve the active variant for a kind once, so the per-block branches
    // below don't repeat the kind switch.
    Enum resolvedFor(VariantKind kind) => switch (kind) {
      VariantKind.starter => resolvedStarter,
      VariantKind.hearts => resolvedHearts,
    };
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
                      TextSpan(text: '${i + 1}.  '),
                      switch (b.items[i]) {
                        final TextItem item => _parseInline(
                          item.text,
                          tt.bodyMedium ?? const TextStyle(),
                        ),
                        final VariantItem item => _parseInline(
                          item.block.textFor(
                            resolvedFor(item.block.variantKind),
                          ),
                          tt.bodyMedium ?? const TextStyle(),
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
        child: RulesNoteCallout(label: b.label, text: b.text),
      ),
      final VariantBlock b => _VariantBlockView(
        block: b,
        resolvedVariant: resolvedFor(b.variantKind),
        editMode: editMode,
      ),
    };
  }
}

class _VariantBlockView extends StatelessWidget {
  const _VariantBlockView({
    required this.block,
    required this.resolvedVariant,
    required this.editMode,
  });

  final VariantBlock block;
  final Enum resolvedVariant;
  final RulesEditMode editMode;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final String text = block.textFor(resolvedVariant);
    final settingsIcon = switch (editMode) {
      RulesEditMode.enabled => _SettingsIconButton(
        variantKind: block.variantKind,
        resolvedVariant: resolvedVariant,
      ),
      RulesEditMode.hidden => null,
      RulesEditMode.disabled => const _DisabledSettingsIconButton(),
    };
    return block.label != null
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 2),
            child: RulesNoteCallout(
              label: block.label!,
              text: text,
              trailing: settingsIcon,
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(child: Text(text, style: tt.bodyMedium)),
                ?settingsIcon,
              ],
            ),
          );
  }
}

/// Material 3 highlighted callout used to render [Note] and labeled
/// [VariantBlock] blocks. The label is always rendered as a bold header row
/// (with [trailing] on the right when provided, e.g. a settings icon),
/// followed by [text] on the next line.
class RulesNoteCallout extends StatelessWidget {
  const RulesNoteCallout({
    super.key,
    this.label,
    required this.text,
    this.trailing,
  });

  final String? label;
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
    return Container(
      decoration: decoration,
      padding: EdgeInsets.fromLTRB(
        10,
        label != null ? 4 : 8,
        trailing != null ? 4 : 12,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
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
                ?trailing,
              ],
            ),
          if (label != null) const SizedBox(height: 2),
          Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
        ],
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

class _DisabledSettingsIconButton extends StatelessWidget {
  const _DisabledSettingsIconButton();

  @override
  Widget build(BuildContext context) {
    final color = disabledOnSurface(Theme.of(context).colorScheme);
    return IconButton(
      icon: Icon(Symbols.settings, color: color),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      tooltip: 'Spelregel variant',
      onPressed: () => showIncompleteFormSnackBar(
        ScaffoldMessenger.of(context),
        message:
            "Je kunt de spelregelvarianten hier nu niet wijzigen. Ga naar het beginscherm of gebruik de knop 'Spel bewerken'.",
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
    final subtitle = switch (widget.variantKind) {
      VariantKind.starter => kStarterVariantSectionSubtitle,
      VariantKind.hearts => kHeartsVariantSectionSubtitle,
    };
    return AlertDialog(
      title: const Text('Spelregel variant'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            switch (widget.variantKind) {
              VariantKind.starter => VariantRadioList<StarterVariant>(
                values: StarterVariant.values,
                value: _pending as StarterVariant,
                onChanged: (v) => setState(() => _pending = v),
                contentPadding: EdgeInsets.zero,
              ),
              VariantKind.hearts => VariantRadioList<HeartsVariant>(
                values: HeartsVariant.values,
                value: _pending as HeartsVariant,
                onChanged: (v) => setState(() => _pending = v),
                contentPadding: EdgeInsets.zero,
              ),
            },
          ],
        ),
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
              .setValue(_pending as StarterVariant),
        );
      case VariantKind.hearts:
        unawaited(
          ref
              .read(defaultHeartsVariantProvider.notifier)
              .setValue(_pending as HeartsVariant),
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
