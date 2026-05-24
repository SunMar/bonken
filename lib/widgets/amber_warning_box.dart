import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme_extensions.dart';

/// Boxed amber callout used to surface non-blocking warnings (player
/// reorder reminders, "score is not yet complete", …). Reads
/// [WarningColors] from the active [ThemeData] with a brightness-based
/// fallback so the widget still renders in unthemed test harnesses.
class AmberWarningBox extends StatelessWidget {
  const AmberWarningBox({super.key, this.label, required this.text});

  /// Optional bold heading rendered above [text]. When `null` (the
  /// default) only the body line is shown.
  final String? label;

  /// Body text. Required.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning =
        theme.extension<WarningColors>() ??
        (theme.brightness == Brightness.dark
            ? WarningColors.dark
            : WarningColors.light);
    final tt = theme.textTheme;
    // GitHub Alert style: icon + title on the first line, body text below.
    // Without a label the icon sits inline before the body text.
    final Widget content;
    if (label != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Label already signals the warning type — icon stays silent.
              Icon(Symbols.warning_amber, size: 20, color: warning.icon),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label!,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: warning.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(text, style: tt.bodyMedium?.copyWith(color: warning.foreground)),
        ],
      );
    } else {
      content = Row(
        // Center so the icon aligns with the mid-point of multi-line text.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // No label — icon alone conveys "warning" to screen readers.
          Icon(
            Symbols.warning_amber,
            size: 20,
            color: warning.icon,
            semanticLabel: 'Waarschuwing',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(color: warning.foreground),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: warning.background,
        border: Border.all(color: warning.border, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: content,
    );
  }
}
