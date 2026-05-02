import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Standard list of player names used by the widget tests.
const playerNames = ['Alice', 'Bob', 'Carol', 'Dan'];

/// Wraps [child] in a [MaterialApp]+[Scaffold] and pumps it.
Future<void> pumpHost(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
