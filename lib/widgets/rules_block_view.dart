import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/game_rules.dart';
import '../models/hearts_variant.dart';
import '../models/labeled_variant.dart';
import '../models/starter_variant.dart';
import '../state/default_hearts_variant_provider.dart';
import '../state/default_starter_variant_provider.dart';
import '../state/rules_edit_mode_provider.dart';
import '../state/settings_provider.dart';
import '../utils.dart';
import 'disabled_tap_detector.dart';
import 'timed_snackbar.dart';
import 'variant_radio_list.dart';

/// Renders a single [Block] from [game_rules.dart] as Material widgets.
///
/// This is the canonical Flutter renderer for the structured rules data and
/// is shared between the full rules screen and the per-game rules screen.
/// Anything visual about how a block looks lives here, not in the data.
///
/// The active variant for each kind comes from the default-variant providers,
/// and [rulesEditModeProvider] decides whether variant-sensitive blocks expose
/// the settings icon and "Spelregelvariant" alternative. `RulesIconButton`
/// overrides both (scoped to the pushed route) when rules are opened from
/// within a game, so the player sees only their committed rule set.
class RulesBlockView extends ConsumerWidget {
  const RulesBlockView({super.key, required this.block});

  final Block block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final base = tt.bodyMedium ?? const TextStyle();
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
      .starter => resolvedStarter,
      .hearts => resolvedHearts,
    };
    return switch (block) {
      // The root span from _parseInline already carries `base`, so Para/RichPara
      // don't repeat the body style on the outer Text.rich.
      final Para b => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(_parseInline(b.text, base)),
      ),
      final RichPara b => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(
          TextSpan(
            style: tt.bodyMedium,
            children: [
              for (final span in b.spans)
                switch (span) {
                  final InlineText s => _parseInline(s.text, base),
                  final InlineIcon s => WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(s.icon, size: 14, color: tt.bodyMedium?.color),
                  ),
                },
            ],
          ),
        ),
      ),
      final BulletList b => _markedList([
        for (final item in b.items)
          (marker: '•  ', body: _parseInline(item, base)),
      ], tt.bodyMedium),
      final NumberedList b => _markedList([
        for (int i = 0; i < b.items.length; i++)
          (
            marker: '${i + 1}.  ',
            body: switch (b.items[i]) {
              final TextItem item => _parseInline(item.text, base),
              final VariantItem item => _parseInline(
                item.block.textFor(resolvedFor(item.block.variantKind)),
                base,
              ),
            },
          ),
      ], tt.bodyMedium),
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
      .enabled => _VariantSettingsIconButton(
        onOpen: () =>
            _openVariantDialog(context, block.variantKind, resolvedVariant),
      ),
      .hidden => null,
      .disabled => const _VariantSettingsIconButton(),
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
          if (label != null) ...[
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
            const SizedBox(height: 2),
          ],
          Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
        ],
      ),
    );
  }
}

/// The settings cog shown on variant-sensitive rule blocks. When [onOpen] is
/// non-null the cog opens the variant picker; when null it is rendered *truly
/// disabled* (Mechanism A — ARCHITECTURE §2) with a transparent overlay that
/// explains where the variants can be changed instead.
class _VariantSettingsIconButton extends StatelessWidget {
  const _VariantSettingsIconButton({this.onOpen});

  /// Opens the variant picker. `null` ⇒ the cog is disabled.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cog = IconButton(
      icon: const Icon(Symbols.settings),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      tooltip: 'Spelregelvariant',
      onPressed: onOpen,
    );
    if (onOpen != null) return cog;
    // Disabled: keep the cog truly disabled (native M3 disabled colours —
    // announced disabled, so WCAG contrast-exempt) while a transparent overlay
    // catches the tap and explains why. A manual 0.38 dim on an interactive
    // button would fail the 3:1 non-text contrast floor for an enabled control.
    return DisabledTapDetector(
      enabled: true,
      onTap: () => showTimedSnackBar(
        ScaffoldMessenger.of(context),
        content: const Text(
          "Je kunt de spelregelvarianten hier nu niet wijzigen. Ga naar het beginscherm of gebruik de knop 'Spel bewerken'.",
        ),
      ),
      child: cog,
    );
  }
}

/// Opens the variant picker for [kind], pre-selecting [resolved].
///
/// This `switch (kind)` is the *only* place the kind is mapped to its concrete
/// variant type (subtitle + value list + persist call); the dialog itself is
/// generic, so it carries no per-kind switch and no `as` casts.
void _openVariantDialog(BuildContext context, VariantKind kind, Enum resolved) {
  final Widget dialog = switch (kind) {
    .starter => _VariantDialog<StarterVariant>(
      subtitle: kStarterVariantSectionSubtitle,
      values: StarterVariant.values,
      initialVariant: resolved as StarterVariant,
      persist: (ref, v) =>
          ref.read(settingsProvider.notifier).setDefaultStarterVariant(v),
    ),
    .hearts => _VariantDialog<HeartsVariant>(
      subtitle: kHeartsVariantSectionSubtitle,
      values: HeartsVariant.values,
      initialVariant: resolved as HeartsVariant,
      persist: (ref, v) =>
          ref.read(settingsProvider.notifier).setDefaultHeartsVariant(v),
    ),
  };
  unawaited(showDialog<void>(context: context, builder: (_) => dialog));
}

/// Deferred-save picker for a single variant kind. Generic over the concrete
/// variant type [T] so [_VariantDialogState._pending], the [VariantRadioList]
/// and [persist] are all statically typed — the kind→type mapping happens once,
/// in [_openVariantDialog]. Composes the same [VariantRadioList] used by
/// [GameRulesSections]; the difference is lifecycle (Save/Cancel commit here vs
/// immediate-apply there), which is why the picker isn't shared wholesale.
class _VariantDialog<T extends LabeledVariant> extends ConsumerStatefulWidget {
  const _VariantDialog({
    required this.subtitle,
    required this.values,
    required this.initialVariant,
    required this.persist,
  });

  final String subtitle;
  final List<T> values;
  final T initialVariant;

  /// Persists the chosen value when the user taps Save. Receives the dialog's
  /// own [WidgetRef] (the call site has none).
  final Future<void> Function(WidgetRef ref, T value) persist;

  @override
  ConsumerState<_VariantDialog<T>> createState() => _VariantDialogState<T>();
}

class _VariantDialogState<T extends LabeledVariant>
    extends ConsumerState<_VariantDialog<T>> {
  late T _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.initialVariant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Spelregelvariant'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            VariantRadioList<T>(
              values: widget.values,
              value: _pending,
              onChanged: (v) => setState(() => _pending = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        FilledButton(onPressed: _save, child: const Text(kSaveLabel)),
      ],
    );
  }

  void _save() {
    unawaited(widget.persist(ref, _pending));
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

/// Renders a marker + body span per row in a left-indented column — the shared
/// scaffold of [BulletList] and [NumberedList]. The marker span is styleless and
/// inherits [bodyStyle] from the row's `Text.rich` (load-bearing — the inner
/// marker span carries no style of its own).
Widget _markedList(
  List<({String marker, InlineSpan body})> rows,
  TextStyle? bodyStyle,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: row.marker),
                  row.body,
                ],
              ),
              style: bodyStyle,
            ),
          ),
      ],
    ),
  );
}

/// Matches `**bold**` runs. Hoisted to a top-level `final` so it compiles once,
/// not on every [_parseInline] call.
final _boldPattern = RegExp(r'\*\*(.+?)\*\*');

/// Tiny `**bold**` parser → [TextSpan].
TextSpan _parseInline(String text, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  final re = _boldPattern;
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
