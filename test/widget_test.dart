import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: BonkenApp()),
    );
    expect(find.text('Bonken'), findsWidgets);
  });
}
