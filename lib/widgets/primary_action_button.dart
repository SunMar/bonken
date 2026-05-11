import 'package:flutter/material.dart';

/// Hero action button used at the bottom of full-screen flows
/// ("Nieuw spel", "Start spel", "Nieuw spel met dezelfde spelers", …).
///
/// Centralises the "tall FilledButton with leading icon" pattern so all
/// primary CTAs are visually consistent and bumping the size or padding
/// later only requires editing one place.
///
/// Use this for *primary actions on a screen surface* — not for buttons
/// inside dialogs, list rows, or the AppBar (those should stay default).
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final Widget label;
  final VoidCallback? onPressed;

  /// Vertical padding that gives the hero button its prominent height.
  /// 18 sits between Material 3's "extended" FAB (16) and a fully-padded
  /// pill (24); it visibly stands out above standard FilledButtons in
  /// dialogs/cards without dominating the screen.
  static const double _verticalPadding = 18;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: icon,
      label: label,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
      ),
      onPressed: onPressed,
    );
  }
}
