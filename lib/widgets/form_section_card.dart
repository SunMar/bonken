import 'package:flutter/material.dart';

/// A card with a labelled section header, an optional subtitle, and arbitrary
/// [child] content. Used on every form-style screen (new-game, edit-game,
/// settings) to keep the Semantics header, title style, subtitle colour, and
/// card padding consistent.
///
/// ```
/// FormSectionCard(
///   title: 'Spelers',
///   subtitle: 'Voer de namen van de 4 spelers in.',
///   child: PlayerListField(...),
/// )
/// ```
class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.childSpacing = 12.0,
  });

  final String title;

  /// Optional paragraph shown between the title and [child].
  final String? subtitle;

  final Widget child;

  /// Outer padding for the card content. Defaults to `all(16)`.
  final EdgeInsetsGeometry padding;

  /// Vertical gap between the subtitle (or title when no subtitle) and
  /// [child]. Defaults to `12`.
  final double childSpacing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormSectionHeader(title: title, subtitle: subtitle),
            SizedBox(height: childSpacing),
            child,
          ],
        ),
      ),
    );
  }
}

/// The header portion of a form section: a [Semantics] header with the
/// [title] in `titleSmall`, and an optional [subtitle] paragraph in
/// `bodyMedium`/`onSurfaceVariant`. Used by [FormSectionCard] (inside its
/// card) and by the "Spelregels" expansion sections, so the header look stays
/// identical whether or not it sits inside a card.
class FormSectionHeader extends StatelessWidget {
  const FormSectionHeader({super.key, required this.title, this.subtitle});

  final String title;

  /// Optional paragraph shown below the title.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
