import 'dart:convert';

import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/storage_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

// Minimal v1 settings blob with custom variant values.
Map<String, dynamic> _settingsBlob({
  String starterVariant = 'dealerStarts',
  String heartsVariant = 'onlyAfterPlayedHeart',
  String themeMode = 'system',
}) => {
  'version': 1,
  'themeMode': themeMode,
  'ruleVariants': {
    'starterVariant': starterVariant,
    'heartsVariant': heartsVariant,
  },
};

void main() {
  setUpPrefs();

  // -----------------------------------------------------------------------
  // loadPersistedSettings — starter variant
  // -----------------------------------------------------------------------
  group('loadPersistedSettings — starter variant', () {
    test('returns dealerStarts when nothing is stored', () async {
      final result = await loadPersistedSettings();
      expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
    });

    test('returns stored value when it matches a known name', () async {
      setAsyncPrefs({
        settingsStorageKey: jsonEncode(
          _settingsBlob(starterVariant: 'oppositeChooserStarts'),
        ),
      });
      final result = await loadPersistedSettings();
      expect(
        result.defaultStarterVariant,
        StarterVariant.oppositeChooserStarts,
      );
    });

    test(
      'throws CorruptPersistenceException for an unrecognised stored name',
      () async {
        setAsyncPrefs({
          settingsStorageKey: jsonEncode(
            _settingsBlob(starterVariant: 'notAVariant'),
          ),
        });
        await expectLater(
          loadPersistedSettings(),
          throwsA(isA<CorruptPersistenceException>()),
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // loadPersistedSettings — hearts variant
  // -----------------------------------------------------------------------
  group('loadPersistedSettings — hearts variant', () {
    test('returns onlyAfterPlayedHeart when nothing is stored', () async {
      final result = await loadPersistedSettings();
      expect(result.defaultHeartsVariant, HeartsVariant.onlyAfterPlayedHeart);
    });

    test('returns stored value when it matches a known name', () async {
      setAsyncPrefs({
        settingsStorageKey: jsonEncode(
          _settingsBlob(heartsVariant: 'graduatedUnlock'),
        ),
      });
      final result = await loadPersistedSettings();
      expect(result.defaultHeartsVariant, HeartsVariant.graduatedUnlock);
    });

    test(
      'throws CorruptPersistenceException for an unrecognised stored name',
      () async {
        setAsyncPrefs({
          settingsStorageKey: jsonEncode(_settingsBlob(heartsVariant: 'nope')),
        });
        await expectLater(
          loadPersistedSettings(),
          throwsA(isA<CorruptPersistenceException>()),
        );
      },
    );
  });
}
