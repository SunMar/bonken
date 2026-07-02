import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Signature for the camera scanner preview embedded in the QR-scanner screen.
///
/// [onDetect] fires with the raw decoded string of a scanned code; [onUnavailable]
/// fires when the camera cannot be used (permission denied or no camera).
typedef QrScannerView =
    Widget Function({
      required void Function(String raw) onDetect,
      required VoidCallback onUnavailable,
    });

/// DI seam for the camera preview — a platform side-effect that cannot run under
/// widget tests (there is no real camera). Production returns a [MobileScanner];
/// tests override this to inject a fake that emits a canned barcode or an error.
/// See ARCHITECTURE.md.
final qrScannerViewProvider = Provider<QrScannerView>(
  (ref) =>
      ({required onDetect, required onUnavailable}) =>
          _MobileScannerView(onDetect: onDetect, onUnavailable: onUnavailable),
);

class _MobileScannerView extends StatefulWidget {
  const _MobileScannerView({
    required this.onDetect,
    required this.onUnavailable,
  });

  final void Function(String raw) onDetect;
  final VoidCallback onUnavailable;

  @override
  State<_MobileScannerView> createState() => _MobileScannerViewState();
}

class _MobileScannerViewState extends State<_MobileScannerView> {
  // errorBuilder can be invoked on every rebuild; report the unavailable camera
  // only once.
  bool _reportedError = false;

  @override
  Widget build(BuildContext context) {
    // No explicit controller: MobileScanner creates and lifecycle-manages its own
    // (start on mount, stop/dispose on unmount). The OS camera-permission prompt
    // is triggered by that start — i.e. only once the user opens this screen.
    return MobileScanner(
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.isNotEmpty) {
            widget.onDetect(raw);
            return;
          }
        }
      },
      errorBuilder: (context, error) {
        if (!_reportedError) {
          _reportedError = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onUnavailable(),
          );
        }
        return const ColoredBox(color: Colors.black);
      },
    );
  }
}
