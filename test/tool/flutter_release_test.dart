// Tests for tool/helpers/flutter_release.dart.
// No network — uses the checked-in fixture at test/tool/fixtures/releases.json.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/helpers/flutter_release.dart';

void main() {
  late Map<String, dynamic> fixtureData;

  setUpAll(() {
    final fixture = File('test/tool/fixtures/releases.json').readAsStringSync();
    fixtureData = jsonDecode(fixture) as Map<String, dynamic>;
  });

  test('parseLatestStable extracts the stable (Flutter, Dart) pair', () {
    final (flutter, dart) = parseLatestStable(fixtureData);
    expect(flutter, '3.44.0');
    expect(dart, '3.12.0'); // build suffix stripped
  });

  test('parseLatestStable strips dart_sdk_version build suffix', () {
    // The fixture stable entry has "3.12.0 (build 3.12.0.500)".
    final (_, dart) = parseLatestStable(fixtureData);
    expect(dart, isNot(contains('build')));
    expect(dart, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test('parseLatestStable throws StateError when stable hash is missing', () {
    final bad = Map<String, dynamic>.from(fixtureData);
    (bad['current_release'] as Map)['stable'] = 'nonexistent-hash';
    expect(() => parseLatestStable(bad), throwsStateError);
  });
}
