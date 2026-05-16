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
    return Container(
      decoration: BoxDecoration(
        color: warning.background,
        border: Border.all(color: warning.border, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Symbols.warning_amber, size: 20, color: warning.icon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label!,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: warning.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: tt.bodyMedium?.copyWith(color: warning.foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
