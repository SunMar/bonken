import 'package:flutter/material.dart';

import 'disabled_tappable_button.dart';

/// Full-width [FilledButton.icon] for use as the sole action in a
/// [BottomAppBar]. Uses a 48 dp minimum height so the button looks visually
/// proportional at full screen width (wide buttons appear shorter at 40 dp).
///
/// Composes [DisabledTappableButton] (Mechanism A): when [onPressed] is null
/// and [onDisabledTap] is provided, the button is truly disabled (native M3
/// disabled colours preserved) and a transparent overlay fires [onDisabledTap]
/// on tap so users learn *why* the action is not available yet.
class FullWidthBottomBarButton extends StatelessWidget {
  const FullWidthBottomBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onDisabledTap,
  });

  final Widget icon;
  final Widget label;
  final VoidCallback? onPressed;
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: Row(
        children: [
          Expanded(
            child: DisabledTappableButton(
              onPressed: onPressed,
              onDisabledTap: onDisabledTap,
              builder: (onPressed) => FilledButton.icon(
                icon: icon,
                label: label,
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 48)),
                ),
                onPressed: onPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
