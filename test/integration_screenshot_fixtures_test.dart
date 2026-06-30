// Guards the screenshot integration-test fixtures
// (integration_test/screenshot_fixtures.dart) against drift in the storage
// format, enums, or migrations. They are seeded into the real app on a device by
// the screenshot workflow, so an invalid value (e.g. a renamed enum) makes the
// import fail, the home shows no games, and every later screenshot step fails —
// but only in the manual screenshots job, never in the regular suite. This test
// exercises the same encode → decode → migrate → validate path the screenshot
// test now seeds through (`_seedGames`), so a bad fixture fails here instead.
//
// Regression: the fixtures shipped `heartsVariant: "anytime"`, a value that was
// never a real HeartsVariant, breaking the screenshot run after the 0.22.0
// storage refactor made parsing strict.

import 'dart:convert';

import 'package:bonken/models/app_version.dart';
import 'package:bonken/models/game_session.dart';
import 'package:bonken/state/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/screenshot_fixtures.dart';

/// Mirrors the data path the screenshot test seeds through (`_seedGames`): the
/// fixture is encoded to a backup ZIP and run back through [BackupCodec.decode],
/// which decodes → migrates → validates the games stream exactly as
/// [ImportNotifier.applyImport] then commits it. A drifted fixture (renamed
/// enum, bad shape, version past current) yields a non-[StreamValid] stream, so
/// [DecodedBackup.games] is null and the expectation fails with the cause.
Future<List<GameSession>> loadFixture(Map<String, dynamic> fixture) async {
  final zip = BackupCodec.encode(
    appVersion: const AppVersion(version: '1.0.0', buildNumber: '1'),
    gamesJson: jsonEncode(fixture),
  );
  final decoded = await BackupCodec.decode(zip);
  expect(
    decoded.games,
    isNotNull,
    reason:
        'fixture must decode + migrate + validate cleanly; '
        'got ${decoded.gamesStatus}',
  );
  return decoded.games!;
}

void main() {
  test('sessionAFixture seeds through the import pipeline', () async {
    expect(await loadFixture(sessionAFixture), hasLength(2));
  });

  test('sessionBFixture seeds through the import pipeline', () async {
    expect(await loadFixture(sessionBFixture), hasLength(4));
  });
}
