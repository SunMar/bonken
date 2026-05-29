import 'package:flutter/material.dart';

/// A card with a labelled section header, an optional subtitle, and arbitrary
/// [child] content. Used on every form-style screen (new-game, edit-players,
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
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
            SizedBox(height: childSpacing),
            child,
          ],
        ),
      ),
    );
  }
}
