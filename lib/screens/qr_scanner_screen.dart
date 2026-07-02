import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_session.dart';
import '../navigation/app_routes.dart';
import '../state/calculator_keep_alive.dart';
import '../state/calculator_provider.dart';
import '../state/game_history_provider.dart';
import '../state/game_import.dart';
import '../state/game_qr_codec.dart';
import '../state/highlight_game_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/timed_snackbar.dart';

/// Title of the scanner screen and the tooltip of the Home button that opens it.
const String kScanQrTitle = 'QR-code scannen';

/// Shown when the camera is denied or unavailable.
const String kCameraUnavailableMessage = 'Camera niet beschikbaar';

/// Shown when a scanned code is not a (valid) Bonken game QR.
const String kInvalidQrMessage = 'Ongeldige QR-code';

/// Shown when a scanned game was made by a newer version of the app.
const String kQrTooNewMessage =
    'Deze QR-code is met een nieuwere versie van Bonken gemaakt';

/// Title of the overwrite-confirmation dialog.
const String kGameExistsTitle = 'Dit spel bestaat al';

/// Confirm label of the overwrite dialog.
const String kOverwriteButton = 'Overschrijven';

/// Full-screen camera QR scanner for importing a shared game, opened from Home.
///
/// Decodes scanned codes via [GameQrCodec]; a valid game is imported (respecting
/// same-id duplicates) and opened. Invalid / too-new codes show a snackbar and
/// keep scanning; a denied/absent camera shows a snackbar and returns Home.
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  /// Set once a valid game is being imported — stops any further handling.
  bool _handled = false;

  /// The last raw string reacted to, so a code held in view (which the scanner
  /// re-emits many times a second) triggers its snackbar only once.
  String? _lastRaw;

  void _snack(String message) =>
      showTimedSnackBar(ScaffoldMessenger.of(context), content: Text(message));

  void _onDetect(String raw) {
    if (_handled || raw == _lastRaw) return;
    _lastRaw = raw;
    switch (GameQrCodec.decode(raw)) {
      case GameQrInvalid():
        _snack(kInvalidQrMessage);
      case GameQrTooNew():
        _snack(kQrTooNewMessage);
      case GameQrOk(:final game):
        _handled = true;
        unawaited(_import(game));
    }
  }

  void _onCameraUnavailable() {
    if (_handled || !mounted) return;
    _handled = true;
    _snack(kCameraUnavailableMessage);
    unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _import(GameSession game) async {
    final history = ref.read(gameHistoryProvider).value ?? const [];

    switch (classifyGameImport(game, history)) {
      case GameImportNew():
        await ref.read(gameHistoryProvider.notifier).saveGame(game);
        if (!mounted) return;
        _openGame(game);
      case GameImportIdentical(:final existing):
        // Same id, same data → nothing to write; just open the existing game.
        _openGame(existing);
      case GameImportConflict(:final existing):
        final overwrite = await _confirmOverwrite();
        if (!mounted) return;
        if (overwrite) {
          await ref.read(gameHistoryProvider.notifier).saveGame(game);
          if (!mounted) return;
          _openGame(game);
        } else {
          // Leave the existing game untouched; return Home and flash it so the
          // user can find and compare it.
          ref.read(highlightGameProvider.notifier).flash(existing.id);
          Navigator.of(context).pop();
        }
    }
  }

  Future<bool> _confirmOverwrite() async {
    final confirmed = await showConfirmDialog(
      context,
      title: kGameExistsTitle,
      contentText:
          'Dit spel zit al in je spelgeschiedenis, maar met andere gegevens. '
          'Wil je het overschrijven?',
      confirmLabel: kOverwriteButton,
      destructive: true,
    );
    return confirmed ?? false;
  }

  void _openGame(GameSession session) {
    holdCalculatorAcrossNavigation(context);
    ref.read(calculatorProvider.notifier).loadSession(session);
    // Replace the scanner with the game so Back from the game returns to Home,
    // not to the camera.
    unawaited(AppRoutes.replaceWithGame(context));
  }

  @override
  Widget build(BuildContext context) {
    final scannerView = ref.watch(qrScannerViewProvider);
    return AppScaffold(
      appBar: AppBar(title: const Text(kScanQrTitle)),
      body: scannerView(
        onDetect: _onDetect,
        onUnavailable: _onCameraUnavailable,
      ),
    );
  }
}
