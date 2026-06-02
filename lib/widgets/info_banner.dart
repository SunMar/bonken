import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A card-styled info banner: secondaryContainer background, info icon, and
/// arbitrary [child] content. Shared across screens that show contextual notes.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Symbols.info,
                size: 24,
                color: cs.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
