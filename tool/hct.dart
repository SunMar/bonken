// ignore_for_file: avoid_print, depend_on_referenced_packages

// Convert between sRGB hex and HCT (hue, chroma, tone) using Google's
// material_color_utilities — the canonical implementation behind
// Material 3's tonal palettes.
//
// Two modes — direction is always explicit:
//
//   1. Hex -> HCT
//      dart run tool/hct.dart to 5BD79A FF6F74 '#1F6A47'
//      Accepts: RRGGBB, #RRGGBB, AARRGGBB, #AARRGGBB (alpha is ignored).
//
//   2. HCT -> Hex
//      dart run tool/hct.dart from 162,54,80 18,65,80
//      Each argument is a comma-separated H,C,T triplet. Note that sRGB
//      cannot represent every HCT coordinate; clipped values are reported
//      with their actual HCT.

import 'package:material_color_utilities/material_color_utilities.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    _usage();
    return;
  }
  final rest = args.skip(1).toList();
  switch (args.first) {
    case 'to':
      _toHct(rest);
    case 'from':
      _fromHct(rest);
    default:
      _usage();
  }
}

void _usage() {
  print('Usage: dart run tool/hct.dart to    RRGGBB  [RRGGBB ...]');
  print('       dart run tool/hct.dart from  H,C,T   [H,C,T ...]');
}

void _toHct(List<String> args) {
  if (args.isEmpty) {
    _usage();
    return;
  }
  for (final raw in args) {
    final hex = raw.replaceFirst('#', '').toUpperCase();
    final rgb = hex.length == 8 ? hex.substring(2) : hex;
    if (rgb.length != 6 || int.tryParse(rgb, radix: 16) == null) {
      print('#$hex  invalid hex');
      continue;
    }
    final argb = int.parse('FF$rgb', radix: 16);
    final h = Hct.fromInt(argb);
    print(
      '#$rgb  '
      'H ${h.hue.toStringAsFixed(1).padLeft(5)}  '
      'C ${h.chroma.toStringAsFixed(1).padLeft(5)}  '
      'T ${h.tone.toStringAsFixed(1).padLeft(5)}',
    );
  }
}

void _fromHct(List<String> args) {
  if (args.isEmpty) {
    _usage();
    return;
  }
  for (final raw in args) {
    final parts = raw.split(',');
    if (parts.length != 3) {
      print('$raw  expected H,C,T (three comma-separated numbers)');
      continue;
    }
    final h = double.tryParse(parts[0].trim());
    final c = double.tryParse(parts[1].trim());
    final t = double.tryParse(parts[2].trim());
    if (h == null || c == null || t == null) {
      print('$raw  non-numeric component');
      continue;
    }
    final hct = Hct.from(h, c, t);
    final argb = hct.toInt();
    final hex = (argb & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    final rt = Hct.fromInt(argb);
    print(
      'H $h C $c T $t  ->  #$hex  '
      '(actual H ${rt.hue.toStringAsFixed(1)} '
      'C ${rt.chroma.toStringAsFixed(1)} '
      'T ${rt.tone.toStringAsFixed(1)})',
    );
  }
}
