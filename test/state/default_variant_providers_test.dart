import 'dart:convert';

import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
import 'package:bonken/state/settings_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      SharedPreferences.setMockInitialValues({
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
      'returns dealerStarts fallback for unrecognised stored name',
      () async {
        SharedPreferences.setMockInitialValues({
          settingsStorageKey: jsonEncode(
            _settingsBlob(starterVariant: 'notAVariant'),
          ),
        });
        final result = await loadPersistedSettings();
        expect(result.defaultStarterVariant, StarterVariant.dealerStarts);
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
      SharedPreferences.setMockInitialValues({
        settingsStorageKey: jsonEncode(
          _settingsBlob(heartsVariant: 'graduatedUnlock'),
        ),
      });
      final result = await loadPersistedSettings();
      expect(result.defaultHeartsVariant, HeartsVariant.graduatedUnlock);
    });

    test(
      'returns onlyAfterPlayedHeart fallback for unrecognised stored name',
      () async {
        SharedPreferences.setMockInitialValues({
          settingsStorageKey: jsonEncode(_settingsBlob(heartsVariant: 'nope')),
        });
        final result = await loadPersistedSettings();
        expect(result.defaultHeartsVariant, HeartsVariant.onlyAfterPlayedHeart);
      },
    );
  });

  // -----------------------------------------------------------------------
  // DefaultStarterVariantNotifier (via provider)
  // -----------------------------------------------------------------------
  group('DefaultStarterVariantNotifier', () {
    test('initialises from injected initialVariant', () {
      final c = ProviderContainer(
        overrides: [
          defaultStarterVariantProvider.overrideWith(
            () => DefaultStarterVariantNotifier(
              initialVariant: StarterVariant.oppositeChooserStarts,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(
        c.read(defaultStarterVariantProvider),
        StarterVariant.oppositeChooserStarts,
      );
    });

    test('setValue updates state and persists to settings blob', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c
          .read(defaultStarterVariantProvider.notifier)
          .setValue(StarterVariant.oppositeChooserStarts);
      expect(
        c.read(defaultStarterVariantProvider),
        StarterVariant.oppositeChooserStarts,
      );
      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      final ruleVariants = blob['ruleVariants'] as Map<String, dynamic>;
      expect(ruleVariants['starterVariant'], 'oppositeChooserStarts');
    });

    test('setValue preserves sibling ruleVariants field', () async {
      // Pre-populate so heartsVariant is already set to a non-default value.
      SharedPreferences.setMockInitialValues({
        settingsStorageKey: jsonEncode(
          _settingsBlob(heartsVariant: 'graduatedUnlock'),
        ),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c
          .read(defaultStarterVariantProvider.notifier)
          .setValue(StarterVariant.oppositeChooserStarts);
      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      final ruleVariants = blob['ruleVariants'] as Map<String, dynamic>;
      // Both fields must be present and correct.
      expect(ruleVariants['starterVariant'], 'oppositeChooserStarts');
      expect(ruleVariants['heartsVariant'], 'graduatedUnlock');
    });
  });

  // -----------------------------------------------------------------------
  // DefaultHeartsVariantNotifier (via provider)
  // -----------------------------------------------------------------------
  group('DefaultHeartsVariantNotifier', () {
    test('initialises from injected initialVariant', () {
      final c = ProviderContainer(
        overrides: [
          defaultHeartsVariantProvider.overrideWith(
            () => DefaultHeartsVariantNotifier(
              initialVariant: HeartsVariant.graduatedUnlock,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(
        c.read(defaultHeartsVariantProvider),
        HeartsVariant.graduatedUnlock,
      );
    });

    test('setValue updates state and persists to settings blob', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c
          .read(defaultHeartsVariantProvider.notifier)
          .setValue(HeartsVariant.graduatedUnlock);
      expect(
        c.read(defaultHeartsVariantProvider),
        HeartsVariant.graduatedUnlock,
      );
      final prefs = await SharedPreferences.getInstance();
      final blob =
          jsonDecode(prefs.getString(settingsStorageKey)!)
              as Map<String, dynamic>;
      final ruleVariants = blob['ruleVariants'] as Map<String, dynamic>;
      expect(ruleVariants['heartsVariant'], 'graduatedUnlock');
    });
  });
}
