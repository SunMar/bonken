import 'dart:convert';

import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  setUpPrefs();

  // -----------------------------------------------------------------------
  // loadPersistedSettings — bootstrap from legacy flat keys
  // -----------------------------------------------------------------------
  group('loadPersistedSettings — bootstrap from legacy flat keys', () {
    test('reads all three legacy keys and writes versioned blob', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'default_starter_variant': 'oppositeChooserStarts',
        'default_hearts_variant': 'graduatedUnlock',
      });
      final result = await loadPersistedSettings();
      expect(result.themeMode, ThemeMode.dark);
      expect(
        result.defaultStarterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(result.defaultHeartsVariant, HeartsVariant.graduatedUnlock);

      final prefs = await SharedPreferences.getInstance();
      // Legacy keys must be deleted.
      expect(prefs.getString('theme_mode'), isNull);
      expect(prefs.getString('default_starter_variant'), isNull);
      expect(prefs.getString('default_hearts_variant'), isNull);
      // Versioned blob must be written.
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      expect(blob['version'], 1);
      expect(blob['themeMode'], 'dark');
      expect(
        (blob['ruleVariants'] as Map)['starterVariant'],
        'oppositeChooserStarts',
      );
    });

    test('uses defaults when no legacy keys exist (fresh install)', () async {
      final result = await loadPersistedSettings();
      expect(result.themeMode, ThemeMode.system);
      expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
      expect(result.defaultHeartsVariant, HeartsVariant.onlyAfterPlayedHeart);

      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      expect(blob['version'], 1);
    });

    test(
      'partial legacy keys — missing values fall back to defaults',
      () async {
        SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
        final result = await loadPersistedSettings();
        expect(result.themeMode, ThemeMode.light);
        expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
        expect(result.defaultHeartsVariant, HeartsVariant.onlyAfterPlayedHeart);
      },
    );

    test('invalid legacy value falls back to default', () async {
      SharedPreferences.setMockInitialValues({
        'default_starter_variant': 'notAVariant',
      });
      final result = await loadPersistedSettings();
      expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
    });
  });

  // -----------------------------------------------------------------------
  // loadPersistedSettings — existing versioned blob
  // -----------------------------------------------------------------------
  group('loadPersistedSettings — existing versioned blob', () {
    test('parses v1 blob correctly', () async {
      SharedPreferences.setMockInitialValues({
        settingsStorageKey: jsonEncode({
          'version': 1,
          'themeMode': 'light',
          'ruleVariants': {
            'starterVariant': 'oppositeChooserStarts',
            'heartsVariant': 'graduatedUnlock',
          },
        }),
      });
      final result = await loadPersistedSettings();
      expect(result.themeMode, ThemeMode.light);
      expect(
        result.defaultStarterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(result.defaultHeartsVariant, HeartsVariant.graduatedUnlock);
    });

    test(
      'throws UnsupportedSettingsVersionException for future version',
      () async {
        SharedPreferences.setMockInitialValues({
          settingsStorageKey: jsonEncode({
            'version': 9999,
            'themeMode': 'system',
          }),
        });
        await expectLater(
          loadPersistedSettings(),
          throwsA(isA<UnsupportedSettingsVersionException>()),
        );
      },
    );

    test('throws CorruptSettingsException for invalid JSON', () async {
      SharedPreferences.setMockInitialValues({
        settingsStorageKey: 'not valid json {{{',
      });
      await expectLater(
        loadPersistedSettings(),
        throwsA(isA<CorruptSettingsException>()),
      );
    });

    test(
      'throws CorruptSettingsException when version key is missing',
      () async {
        SharedPreferences.setMockInitialValues({
          settingsStorageKey: jsonEncode({'themeMode': 'dark'}),
        });
        await expectLater(
          loadPersistedSettings(),
          throwsA(isA<CorruptSettingsException>()),
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // updateSettingsField
  // -----------------------------------------------------------------------
  group('updateSettingsField', () {
    test('writes a top-level field', () async {
      await updateSettingsField(null, 'themeMode', 'dark');
      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      expect(blob['themeMode'], 'dark');
    });

    test('writes a nested field under a section', () async {
      await updateSettingsField(
        'ruleVariants',
        'starterVariant',
        'oppositeChooserStarts',
      );
      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      expect(
        (blob['ruleVariants'] as Map)['starterVariant'],
        'oppositeChooserStarts',
      );
    });

    test('preserves sibling field when updating one nested field', () async {
      // Set both fields, then update only one.
      await updateSettingsField(
        'ruleVariants',
        'heartsVariant',
        'graduatedUnlock',
      );
      await updateSettingsField(
        'ruleVariants',
        'starterVariant',
        'oppositeChooserStarts',
      );
      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      final rv = blob['ruleVariants'] as Map<String, dynamic>;
      expect(rv['starterVariant'], 'oppositeChooserStarts');
      // heartsVariant written first must still be present.
      expect(rv['heartsVariant'], 'graduatedUnlock');
    });

    test('throws ValidationError for an invalid field value', () async {
      await expectLater(
        updateSettingsField(null, 'themeMode', 'neon'),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
