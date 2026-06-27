import 'dart:convert';

import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
import 'package:bonken/state/settings_provider.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:bonken/state/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// A container seeded with [initial] settings (defaults when null), mirroring
/// the `main()`-time `settingsProvider.overrideWith(...)`.
ProviderContainer _container({PersistedSettings? initial}) {
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => SettingsNotifier(initialSettings: initial),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<Map<String, dynamic>> _readBlob() async {
  final prefs = SharedPreferencesAsync();
  return jsonDecode((await prefs.getString(settingsStorageKey))!)
      as Map<String, dynamic>;
}

void main() {
  setUpPrefs();

  group('SettingsNotifier — per-field setters', () {
    test('setThemeMode persists the whole blob and updates the view', () async {
      final c = _container();
      await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);

      expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(c.read(themeModeProvider), ThemeMode.dark);

      final blob = await _readBlob();
      expect(blob['version'], 1);
      expect(blob['themeMode'], 'dark');
      final rv = blob['ruleVariants'] as Map<String, dynamic>;
      // Sibling fields ride along — the whole blob is written every time.
      expect(rv['starterVariant'], 'dealerStarts');
      expect(rv['heartsVariant'], 'onlyAfterPlayedHeart');
    });

    test(
      'setDefaultStarterVariant keeps the in-memory sibling fields',
      () async {
        final c = _container(
          initial: const PersistedSettings(
            themeMode: ThemeMode.dark,
            defaultStarterVariant: StarterVariant.dealerStarts,
            defaultHeartsVariant: HeartsVariant.graduatedUnlock,
          ),
        );
        await c
            .read(settingsProvider.notifier)
            .setDefaultStarterVariant(StarterVariant.oppositeChooserStarts);

        expect(
          c.read(defaultStarterVariantProvider),
          StarterVariant.oppositeChooserStarts,
        );

        final blob = await _readBlob();
        expect(blob['themeMode'], 'dark');
        final rv = blob['ruleVariants'] as Map<String, dynamic>;
        expect(rv['starterVariant'], 'oppositeChooserStarts');
        // Preserved from the in-memory blob, not re-read from disk.
        expect(rv['heartsVariant'], 'graduatedUnlock');
      },
    );

    test('setDefaultHeartsVariant updates only the hearts field', () async {
      final c = _container();
      await c
          .read(settingsProvider.notifier)
          .setDefaultHeartsVariant(HeartsVariant.graduatedUnlock);

      expect(
        c.read(defaultHeartsVariantProvider),
        HeartsVariant.graduatedUnlock,
      );
      final rv = (await _readBlob())['ruleVariants'] as Map<String, dynamic>;
      expect(rv['heartsVariant'], 'graduatedUnlock');
      expect(rv['starterVariant'], 'dealerStarts');
    });
  });

  group('SettingsNotifier — replaceAll (import atomicity)', () {
    test('commits the entire blob in a single write', () async {
      final c = _container();
      await c
          .read(settingsProvider.notifier)
          .replaceAll(
            const PersistedSettings(
              themeMode: ThemeMode.light,
              defaultStarterVariant: StarterVariant.oppositeChooserStarts,
              defaultHeartsVariant: HeartsVariant.graduatedUnlock,
            ),
          );

      // All three derived views reflect the new blob.
      expect(c.read(themeModeProvider), ThemeMode.light);
      expect(
        c.read(defaultStarterVariantProvider),
        StarterVariant.oppositeChooserStarts,
      );
      expect(
        c.read(defaultHeartsVariantProvider),
        HeartsVariant.graduatedUnlock,
      );

      final blob = await _readBlob();
      expect(blob['themeMode'], 'light');
      final rv = blob['ruleVariants'] as Map<String, dynamic>;
      expect(rv['starterVariant'], 'oppositeChooserStarts');
      expect(rv['heartsVariant'], 'graduatedUnlock');
    });
  });

  group('SettingsNotifier — does not re-read the on-disk blob', () {
    test(
      'a write reflects in-memory state, overwriting stale disk values',
      () async {
        // Disk holds values that differ from the in-memory (default) blob.
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
        final c = _container(); // in-memory defaults

        await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);

        // The stale disk values are overwritten from memory, not merged in.
        final blob = await _readBlob();
        expect(blob['themeMode'], 'dark');
        final rv = blob['ruleVariants'] as Map<String, dynamic>;
        expect(rv['starterVariant'], 'dealerStarts');
        expect(rv['heartsVariant'], 'onlyAfterPlayedHeart');
      },
    );
  });
}
