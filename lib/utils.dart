import 'package:flutter/material.dart';

String formatDate(DateTime dt) {
  const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  const months = [
    'jan',
    'feb',
    'mrt',
    'apr',
    'mei',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
  final day = days[dt.weekday - 1];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$day ${dt.day} ${months[dt.month - 1]} ${dt.year}  $h:$m';
}

String formatScore(int score) => score > 0 ? '+$score' : '$score';

/// Material-tinted "success green" used for positive scores and completion icons.
/// Stays consistent across light & dark themes.
const Color successGreen = Color(0xFF2E7D32);

Color scoreColor(int score, ColorScheme cs) => score > 0
    ? successGreen
    : score < 0
    ? cs.error
    : cs.onSurfaceVariant;

/// Background color used for the "redoubled" state across the app.
///
/// In light mode this uses the theme's [ColorScheme.errorContainer]
/// (a soft pastel red).  In dark mode the generated errorContainer is too
/// loud, so a hand-picked muted dark red is used instead.
Color redoubleContainer(ColorScheme cs, Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFF7D3535) : cs.errorContainer;

/// Foreground color paired with [redoubleContainer].
Color onRedoubleContainer(ColorScheme cs, Brightness brightness) =>
    brightness == Brightness.dark
    ? const Color(0xFFFFCDD2)
    : cs.onErrorContainer;
