import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A standard drag handle for use inside a [ReorderableListView] item with
/// `buildDefaultDragHandles: false`.  Wraps [Symbols.drag_indicator] in a
/// [ReorderableDragStartListener] and a grab-cursor [MouseRegion], with the
/// app's standard right padding.
class DragHandle extends StatelessWidget {
  const DragHandle({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(
            Symbols.drag_indicator,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
