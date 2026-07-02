import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/models/player.dart';
import 'package:bonken/navigation/app_routes.dart';
import 'package:bonken/screens/game_screen.dart';
import 'package:bonken/screens/qr_scanner_screen.dart';
import 'package:bonken/state/base45.dart';
import 'package:bonken/state/game_history_provider.dart';
import 'package:bonken/state/game_qr_codec.dart';
import 'package:bonken/state/highlight_game_provider.dart';
import 'package:bonken/state/migrations.dart' show currentStorageVersion;
import 'package:bonken/widgets/qr_scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  setUpPrefs();

  final four = [
    Player(name: 'A'),
    Player(name: 'B'),
    Player(name: 'C'),
    Player(name: 'D'),
  ];

  GameSession session({String? gameName}) => GameSession(
    id: kGameId1,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    scoredAt: DateTime(2024),
    players: four,
    firstDealerId: four.first.id,
    rounds: const [],
    gameName: gameName,
  );

  // Wraps an arbitrary envelope the way the codec does — for the too-new case.
  String encodeEnvelope(Object envelope) {
    final gz = const GZipEncoder().encodeBytes(
      utf8.encode(jsonEncode(envelope)),
    );
    return 'BONKEN:G:1:${Base45.encode(gz)}';
  }

  Future<(ProviderContainer, FakeScannerView)> pumpScanner(
    WidgetTester tester, {
    List<GameSession> existing = const [],
  }) async {
    final fake = FakeScannerView();
    final container = ProviderContainer(
      overrides: [qrScannerViewProvider.overrideWithValue(fake.builder)],
    );
    addTearDown(container.dispose);
    await container.read(gameHistoryProvider.future);
    for (final g in existing) {
      await container.read(gameHistoryProvider.notifier).saveGame(g);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Host()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (container, fake);
  }

  List<GameSession> games(ProviderContainer c) =>
      c.read(gameHistoryProvider).value ?? const [];

  testWidgets('scanning a new game imports it and opens the game', (
    tester,
  ) async {
    final (container, fake) = await pumpScanner(tester);
    fake.emit(GameQrCodec.encode(session(gameName: 'Nieuw')));
    await tester.pump(const Duration(milliseconds: 500)); // import + autosave
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(games(container).where((g) => g.id == kGameId1), hasLength(1));
  });

  testWidgets('scanning an identical existing game just opens it (no dup)', (
    tester,
  ) async {
    final existing = session(gameName: 'Zelfde');
    final (container, fake) = await pumpScanner(tester, existing: [existing]);
    fake.emit(GameQrCodec.encode(existing));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(games(container), hasLength(1));
  });

  testWidgets('a foreign QR shows an error snackbar and keeps scanning', (
    tester,
  ) async {
    final (_, fake) = await pumpScanner(tester);
    fake.emit('https://example.com/not-a-game');
    await tester.pump();
    expect(find.text(kInvalidQrMessage), findsOneWidget);
    // Still on the scanner.
    expect(find.byType(QrScannerScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // drain snackbar timer
    await tester.pumpAndSettle();
  });

  testWidgets('a too-new QR shows the update snackbar', (tester) async {
    final (_, fake) = await pumpScanner(tester);
    fake.emit(
      encodeEnvelope({
        'version': currentStorageVersion + 1,
        'games': [session().toJson()],
      }),
    );
    await tester.pump();
    expect(find.text(kQrTooNewMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('an unavailable camera shows a snackbar and leaves the scanner', (
    tester,
  ) async {
    final (_, fake) = await pumpScanner(tester);
    fake.fail();
    // Settle the pop first: mid-transition the snackbar briefly renders on both
    // the outgoing and incoming Scaffolds, so assert once only the host remains.
    await tester.pumpAndSettle();
    expect(find.text(kCameraUnavailableMessage), findsOneWidget);
    // Popped back to the host.
    expect(find.byType(QrScannerScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // drain snackbar timer
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a same-id game with different data → overwrite replaces + opens',
    (tester) async {
      final (container, fake) = await pumpScanner(
        tester,
        existing: [session(gameName: 'Oud')],
      );
      fake.emit(GameQrCodec.encode(session(gameName: 'Nieuw')));
      await tester.pumpAndSettle();

      expect(find.text(kGameExistsTitle), findsOneWidget);
      await tester.tap(find.text(kOverwriteButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(GameScreen), findsOneWidget);
      final stored = games(container).firstWhere((g) => g.id == kGameId1);
      expect(stored.gameName, 'Nieuw');
    },
  );

  testWidgets('declining the overwrite leaves the game and flags it on home', (
    tester,
  ) async {
    final (container, fake) = await pumpScanner(
      tester,
      existing: [session(gameName: 'Oud')],
    );
    fake.emit(GameQrCodec.encode(session(gameName: 'Nieuw')));
    await tester.pumpAndSettle();

    expect(find.text(kGameExistsTitle), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    // Back on the host, existing game untouched, highlight requested.
    expect(find.byType(QrScannerScreen), findsNothing);
    expect(
      games(container).firstWhere((g) => g.id == kGameId1).gameName,
      'Oud',
    );
    expect(container.read(highlightGameProvider), kGameId1);
  });
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => AppRoutes.openScanQr(context),
        child: const Text('open'),
      ),
    ),
  );
}
