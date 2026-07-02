import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../navigation/app_routes.dart';

/// Tooltip / accessible label of the game-screen "share via QR" action.
const String kShareViaQrTooltip = 'Deel via QR';

/// AppBar action on the game screen that opens the QR-share screen for the
/// current game. Shown for any open game (in-progress or finished) and sits to
/// the left of the finished-game [ShareResultAction].
class ShareQrAction extends StatelessWidget {
  const ShareQrAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.qr_code_2),
      tooltip: kShareViaQrTooltip,
      onPressed: () => unawaited(AppRoutes.openShowQr(context)),
    );
  }
}
