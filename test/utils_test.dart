import 'package:bonken/utils.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Fruit { apple, banana }

void main() {
  group('formatScore', () {
    test('positive score gets a leading +', () {
      expect(formatScore(80), '+80');
    });
    test('zero is shown without sign', () {
      expect(formatScore(0), '0');
    });
    test('negative score keeps the - sign', () {
      expect(formatScore(-50), '-50');
    });
  });

  group('formatDate', () {
    test('formats Monday in January 2024 with weekday/day/month/year/time', () {
      // 2024-01-01 was a Monday at 09:05.
      final s = formatDate(DateTime(2024, 1, 1, 9, 5));
      expect(s, 'ma 1 jan 2024  09:05');
    });

    test('pads single-digit hours and minutes', () {
      final s = formatDate(DateTime(2024, 12, 31, 3, 7));
      expect(s, contains('03:07'));
    });
  });

  group('formatFileDate / formatFileTimestamp', () {
    test('formatFileDate is a zero-padded, sortable yyyy-MM-dd stamp', () {
      expect(formatFileDate(DateTime(2024, 1, 5)), '2024-01-05');
      expect(formatFileDate(DateTime(2024, 12, 31)), '2024-12-31');
    });

    test('formatFileDate pads the year to four digits', () {
      expect(formatFileDate(DateTime(987, 3, 4)), '0987-03-04');
    });

    test('formatFileTimestamp appends a zero-padded HH-mm to the date', () {
      expect(
        formatFileTimestamp(DateTime(2024, 1, 5, 9, 7)),
        '2024-01-05_09-07',
      );
      expect(
        formatFileTimestamp(DateTime(2024, 12, 31, 23, 59)),
        '2024-12-31_23-59',
      );
    });
  });

  group('adjustIndexAfterReorder', () {
    test('target before move (lower than both old & new) is unaffected', () {
      // List: [A, B, C, D]; move C (2) -> after D (target index 3 normalised).
      // Player at index 0 (A) should stay at 0.
      expect(adjustIndexAfterReorder(2, 3, 0), 0);
    });

    test('target equals oldIndex returns the new index', () {
      expect(adjustIndexAfterReorder(1, 3, 1), 3);
      expect(adjustIndexAfterReorder(2, 0, 2), 0);
    });

    test('target after move forward shifts down by one', () {
      // Move 1 -> 3 (normalised); index 2 was after, becomes 1.
      expect(adjustIndexAfterReorder(1, 3, 2), 1);
    });

    test('target after move backward shifts up by one', () {
      // Move 3 -> 1; index 2 was before old, after new -> becomes 3.
      expect(adjustIndexAfterReorder(3, 1, 2), 3);
    });

    test('oldIndex == newIndex leaves target unchanged', () {
      // No actual movement.
      expect(adjustIndexAfterReorder(2, 2, 0), 0);
      expect(adjustIndexAfterReorder(2, 2, 1), 1);
      expect(adjustIndexAfterReorder(2, 2, 3), 3);
    });
  });

  group('reorderPlayerFields', () {
    test('moves the item and keeps the dealer pointing at the same field', () {
      final fields = ['A', 'B', 'C', 'D'];
      // Move C (2) to the front; the dealer was D (index 3).
      final dealer = reorderPlayerFields(fields, 2, 0, 3);
      expect(fields, ['C', 'A', 'B', 'D']);
      // D shifted one seat to the right.
      expect(dealer, 4 - 1); // still D, now at index 3
      expect(fields[dealer!], 'D');
    });

    test('dealer that is the moved field follows it', () {
      final fields = ['A', 'B', 'C', 'D'];
      final dealer = reorderPlayerFields(fields, 1, 3, 1); // dealer is B
      expect(fields, ['A', 'C', 'D', 'B']);
      expect(fields[dealer!], 'B');
    });

    test('null dealer (random) stays null', () {
      final fields = ['A', 'B', 'C', 'D'];
      final dealer = reorderPlayerFields(fields, 0, 2, null);
      expect(fields, ['B', 'C', 'A', 'D']);
      expect(dealer, isNull);
    });

    test('oldIndex == newIndex is a no-op (list and dealer unchanged)', () {
      final fields = ['A', 'B', 'C', 'D'];
      final dealer = reorderPlayerFields(fields, 2, 2, 1);
      expect(fields, ['A', 'B', 'C', 'D']);
      expect(dealer, 1);
    });
  });

  group('enumByNameOrNull', () {
    test('returns the matching value', () {
      expect(enumByNameOrNull(_Fruit.values, 'banana'), _Fruit.banana);
    });
    test('returns null for a null name', () {
      expect(enumByNameOrNull(_Fruit.values, null), isNull);
    });
    test('returns null for an unknown name', () {
      expect(enumByNameOrNull(_Fruit.values, 'cherry'), isNull);
    });
  });

  group('enumByName', () {
    test('returns the matching value', () {
      expect(enumByName(_Fruit.values, 'banana', _Fruit.apple), _Fruit.banana);
    });
    test('returns the fallback when the name is null (absent)', () {
      expect(enumByName(_Fruit.values, null, _Fruit.apple), _Fruit.apple);
    });
    test('throws on a present-but-unknown name (corrupt data)', () {
      expect(
        () => enumByName(_Fruit.values, 'cherry', _Fruit.apple),
        throwsFormatException,
      );
    });
  });
}
