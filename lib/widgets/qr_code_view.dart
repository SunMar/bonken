import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Renders [data] as a QR code. The `qr` package produces only the module
/// matrix, so this widget paints it itself via [_QrPainter].
///
/// Always black-on-white with a 4-module quiet zone, independent of the app
/// theme, so the code scans reliably even in dark mode. Error-correction is
/// [QrErrorCorrectLevel.low] because a screen→camera hand-off is a clean channel
/// and low correction keeps the module density (and so the code) as small and
/// scannable as possible.
class QrCodeView extends StatelessWidget {
  const QrCodeView({
    super.key,
    required this.data,
    this.size = 260,
    this.semanticLabel = 'QR-code',
  });

  /// The string to encode (the `BONKEN:G:1:…` game payload).
  final String data;

  /// Side length of the square code in logical pixels.
  final double size;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final QrImage image;
    try {
      image = QrImage(
        QrCode(
          payload: QrPayload.fromString(data),
          errorCorrectLevel: QrErrorCorrectLevel.low,
        ),
      );
    } on Object {
      // The codec's size-budget test keeps payloads within QR capacity, but if
      // one ever overflows we show a message rather than crash the screen.
      return SizedBox.square(
        dimension: size,
        child: const Center(child: Text('QR-code kon niet worden gemaakt')),
      );
    }
    return Semantics(
      image: true,
      label: semanticLabel,
      child: CustomPaint(
        size: Size.square(size),
        // A white RepaintBoundary-friendly box; the painter fills the quiet zone.
        painter: _QrPainter(image: image, data: data),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.image, required this.data});

  final QrImage image;

  /// The source string — used only for cheap [shouldRepaint] comparison.
  final String data;

  /// Spec-recommended 4-module quiet zone so scanners lock onto the finders.
  static const int _quietModules = 4;

  static final Paint _light = Paint()..color = const Color(0xFFFFFFFF);
  static final Paint _dark = Paint()..color = const Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _light);

    final count = image.moduleCount;
    final moduleSize = size.width / (count + _quietModules * 2);

    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (!image.isDark(row, col)) continue;
        final left = (col + _quietModules) * moduleSize;
        final top = (row + _quietModules) * moduleSize;
        // +0.5 overpaint closes hairline seams between modules from rounding.
        canvas.drawRect(
          Rect.fromLTWH(left, top, moduleSize + 0.5, moduleSize + 0.5),
          _dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.data != data;
}
