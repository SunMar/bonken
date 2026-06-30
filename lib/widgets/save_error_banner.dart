import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Sticky, non-blocking banner shown app-wide (via [AppScaffold]) while writing
/// to local storage is failing — see `saveHealthyProvider`.
///
/// It stays until a later write succeeds (freeing space recovers it on its own).
/// The app remains fully usable from in-memory state meanwhile, so this informs
/// rather than blocks.
class SaveErrorBanner extends StatelessWidget {
  const SaveErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.warning, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Opslaan lukt niet — er is mogelijk te weinig ruimte op je '
                  'toestel. Wat je nu doet kan verloren gaan; maak ruimte vrij.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
