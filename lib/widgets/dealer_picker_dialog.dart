import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/mini_game.dart';

/// Result of [showDealerPickerDialog]: which dealer-selection mode the
/// user picked, plus (for the explicit-pick case) the seat index.
sealed class NextDealerChoice {
  const NextDealerChoice();
}

class NextDealerNext extends NextDealerChoice {
  const NextDealerNext();
}

class NextDealerRandom extends NextDealerChoice {
  const NextDealerRandom();
}

class NextDealerSpecific extends NextDealerChoice {
  const NextDealerSpecific(this.index);
  final int index;
}

/// Shows the "Wie deelt het volgende spel?" picker used when starting a
/// follow-up game with the same players.
///
/// Resolves to `null` if the user dismissed the dialog (Annuleren / back /
/// barrier tap).
Future<NextDealerChoice?> showDealerPickerDialog(
  BuildContext context, {
  required List<String> playerNames,
  required int previousDealerIndex,
}) {
  final nextIndex = (previousDealerIndex + 1) % playerCount;
  return showDialog<NextDealerChoice>(
    context: context,
    builder: (ctx) {
      final tt = Theme.of(ctx).textTheme;
      final cs = Theme.of(ctx).colorScheme;
      Widget choiceTile({
        required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap,
      }) {
        return MergeSemantics(
          child: Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: tt.bodyLarge),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        title: const Text('Wie deelt het volgende spel?'),
        contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              choiceTile(
                icon: Symbols.skip_next,
                title: 'Volgende speler',
                subtitle: playerNames[nextIndex],
                onTap: () => Navigator.pop(ctx, const NextDealerNext()),
              ),
              choiceTile(
                icon: Symbols.shuffle,
                title: 'Willekeurig',
                onTap: () => Navigator.pop(ctx, const NextDealerRandom()),
              ),
              const Divider(height: 16),
              for (int i = 0; i < playerCount; i++)
                choiceTile(
                  icon: Symbols.person,
                  title: playerNames[i],
                  onTap: () => Navigator.pop(ctx, NextDealerSpecific(i)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
        ],
      );
    },
  );
}
