import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bonken/models/player.dart';

/// Standard list of player names used by the widget tests.
const playerNames = ['Alice', 'Bob', 'Carol', 'Dan'];

/// Deterministic player IDs that correspond 1-to-1 with [playerNames].
const playerIds = ['alice', 'bob', 'carol', 'dan'];

/// Player objects with deterministic IDs matching [playerIds] and [playerNames].
final players = [
  Player.fromJson({'id': 'alice', 'name': 'Alice'}),
  Player.fromJson({'id': 'bob', 'name': 'Bob'}),
  Player.fromJson({'id': 'carol', 'name': 'Carol'}),
  Player.fromJson({'id': 'dan', 'name': 'Dan'}),
];

/// Wraps [child] in a [MaterialApp]+[Scaffold] and pumps it.
Future<void> pumpHost(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
