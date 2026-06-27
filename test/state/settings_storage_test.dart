import 'dart:convert';

import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/settings_migrations.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/storage_exceptions.dart';
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
      setAsyncPrefs({
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

      final prefs = SharedPreferencesAsync();
      // Legacy keys must be deleted.
      expect(await prefs.getString('theme_mode'), isNull);
      expect(await prefs.getString('default_starter_variant'), isNull);
      expect(await prefs.getString('default_hearts_variant'), isNull);
      // Versioned blob must be written.
      final blob =
          jsonDecode((await prefs.getString(settingsStorageKey))!)
              as Map<String, dynamic>;
      expect(blob['version'], 1);
      expect(blob['themeMode'], 'dark');
      expect(
        (blob['ruleVariants'] as Map)['starterVariant'],
        'oppositeChooserStarts',
      );
    });

    test('routes the genesis body through the migration chain', () async {
      setAsyncPrefs({
        'theme_mode': 'dark',
        'default_starter_variant': 'oppositeChooserStarts',
        'default_hearts_variant': 'graduatedUnlock',
      });
      await loadPersistedSettings();
      final prefs = SharedPreferencesAsync();
      final written =
          jsonDecode((await prefs.getString(settingsStorageKey))!)
              as Map<String, dynamic>;

      // The bootstrapped blob must equal the full chain applied to a literal-v1
      // seed — proving the genesis builder stamps the version it produces (1)
      // and migrates forward, rather than stamping a moving `current` onto a
      // v1-shaped body that a future v2 step would never upgrade.
      final expected = runSettingsMigrations({
        'version': 1,
        'themeMode': 'dark',
        'ruleVariants': {
          'starterVariant': 'oppositeChooserStarts',
          'heartsVariant': 'graduatedUnlock',
        },
      }, fromVersion: 1);
      expect(written, expected);
    });

    test('uses defaults when no legacy keys exist (fresh install)', () async {
      final result = await loadPersistedSettings();
      expect(result.themeMode, ThemeMode.system);
      expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
      expect(result.defaultHeartsVariant, HeartsVariant.onlyAfterPlayedHeart);

      final prefs = SharedPreferencesAsync();
      final blob =
          jsonDecode((await prefs.getString(settingsStorageKey))!)
              as Map<String, dynamic>;
      expect(blob['version'], 1);
    });

    test(
      'partial legacy keys — missing values fall back to defaults',
      () async {
        setAsyncPrefs({'theme_mode': 'light'});
        final result = await loadPersistedSettings();
        expect(result.themeMode, ThemeMode.light);
        expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
        expect(result.defaultHeartsVariant, HeartsVariant.onlyAfterPlayedHeart);
      },
    );

    test('invalid legacy value throws CorruptPersistenceException', () async {
      setAsyncPrefs({'default_starter_variant': 'notAVariant'});
      // The app only ever wrote valid enum names to the legacy keys, so a
      // present-but-unknown value is corruption — strict, like the versioned blob.
      await expectLater(
        loadPersistedSettings(),
        throwsA(isA<CorruptPersistenceException>()),
      );
    });
  });

  // -----------------------------------------------------------------------
  // loadPersistedSettings — existing versioned blob
  // -----------------------------------------------------------------------
  group('loadPersistedSettings — existing versioned blob', () {
    test('parses v1 blob correctly', () async {
      setAsyncPrefs({
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

    test('throws UnsupportedVersionException for future version', () async {
      setAsyncPrefs({
        settingsStorageKey: jsonEncode({
          'version': 9999,
          'themeMode': 'system',
        }),
      });
      await expectLater(
        loadPersistedSettings(),
        throwsA(isA<UnsupportedVersionException>()),
      );
    });

    test('throws CorruptPersistenceException for invalid JSON', () async {
      setAsyncPrefs({settingsStorageKey: 'not valid json {{{'});
      await expectLater(
        loadPersistedSettings(),
        throwsA(isA<CorruptPersistenceException>()),
      );
    });

    test(
      'throws CorruptPersistenceException when version key is missing',
      () async {
        setAsyncPrefs({
          settingsStorageKey: jsonEncode({'themeMode': 'dark'}),
        });
        await expectLater(
          loadPersistedSettings(),
          throwsA(isA<CorruptPersistenceException>()),
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // persistSettings / settingsToJson
  // -----------------------------------------------------------------------
  group('persistSettings / settingsToJson', () {
    test('writes the full versioned envelope from a typed blob', () async {
      await persistSettings(
        const PersistedSettings(
          themeMode: ThemeMode.dark,
          defaultStarterVariant: StarterVariant.oppositeChooserStarts,
          defaultHeartsVariant: HeartsVariant.graduatedUnlock,
        ),
      );
      final prefs = SharedPreferencesAsync();
      final blob =
          jsonDecode((await prefs.getString(settingsStorageKey))!)
              as Map<String, dynamic>;
      expect(blob['version'], 1);
      expect(blob['themeMode'], 'dark');
      final rv = blob['ruleVariants'] as Map<String, dynamic>;
      expect(rv['starterVariant'], 'oppositeChooserStarts');
      expect(rv['heartsVariant'], 'graduatedUnlock');
    });

    test('round-trips through loadPersistedSettings', () async {
      const settings = PersistedSettings(
        themeMode: ThemeMode.light,
        defaultStarterVariant: StarterVariant.oppositeChooserStarts,
        defaultHeartsVariant: HeartsVariant.graduatedUnlock,
      );
      await persistSettings(settings);
      final loaded = await loadPersistedSettings();
      expect(loaded.themeMode, ThemeMode.light);
      expect(
        loaded.defaultStarterVariant,
        StarterVariant.oppositeChooserStarts,
      );
      expect(loaded.defaultHeartsVariant, HeartsVariant.graduatedUnlock);
    });

    test('settingsToJson stamps the current version', () {
      final json = settingsToJson(const PersistedSettings.defaults());
      expect(json['version'], 1);
      expect(json['themeMode'], 'system');
    });
  });
}
