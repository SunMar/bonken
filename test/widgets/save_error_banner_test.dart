import 'package:bonken/state/save_health_provider.dart';
import 'package:bonken/widgets/app_scaffold.dart';
import 'package:bonken/widgets/save_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SaveErrorBanner shows the out-of-space message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SaveErrorBanner())),
    );
    expect(find.textContaining('Opslaan lukt niet'), findsOneWidget);
  });

  testWidgets(
    'AppScaffold shows the banner only while persistence is unhealthy',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AppScaffold(body: SizedBox.shrink())),
        ),
      );

      // Healthy by default → no banner.
      expect(find.byType(SaveErrorBanner), findsNothing);

      // A failed write flips the flag → banner appears.
      container.read(saveHealthyProvider.notifier).markFailed();
      await tester.pump();
      expect(find.byType(SaveErrorBanner), findsOneWidget);

      // Recovery clears it.
      container.read(saveHealthyProvider.notifier).markOk();
      await tester.pump();
      expect(find.byType(SaveErrorBanner), findsNothing);
    },
  );
}
