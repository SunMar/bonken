import 'package:flutter/material.dart';

/// A single-selection player picker: shows [prompt] above four player buttons.
/// One player is always selected (highlighted).
class PlayerPicker extends StatelessWidget {
  const PlayerPicker({
    required this.playerNames,
    required this.selectedIndex,
    required this.prompt,
    required this.onSelected,
    super.key,
  });

  final List<String> playerNames;
  final int? selectedIndex;
  final String prompt;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 8),
        for (int i = 0; i < playerNames.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _PlayerButton(
            name: playerNames[i],
            isSelected: selectedIndex == i,
            onTap: () => onSelected(i),
          ),
        ],
      ],
    );
  }
}

class _PlayerButton extends StatelessWidget {
  const _PlayerButton({
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
