import 'package:bonken/widgets/qr_code_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpView(WidgetTester tester, String data) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: QrCodeView(data: data)),
      ),
    ),
  );

  testWidgets('renders a painted QR with an image semantics label', (
    tester,
  ) async {
    await pumpView(tester, 'BONKEN:G:1:abcdef');
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.getSemantics(find.bySemanticsLabel('QR-code')), isNotNull);
  });

  testWidgets('data too large for a QR shows a fallback instead of crashing', (
    tester,
  ) async {
    // A QR (v40) holds ~2953 bytes; 4000 chars overflows every version, so the
    // widget must fall back rather than throw.
    await pumpView(tester, 'x' * 4000);
    expect(find.text('QR-code kon niet worden gemaakt'), findsOneWidget);
  });
}
