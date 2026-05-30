import 'package:bonken/models/hearts_variant.dart';
import 'package:bonken/models/starter_variant.dart';
import 'package:bonken/state/default_hearts_variant_provider.dart';
import 'package:bonken/state/default_starter_variant_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  setUpPrefs();

  // -----------------------------------------------------------------------
  // loadPersistedDefaultStarterVariant
  // -----------------------------------------------------------------------
  group('loadPersistedDefaultStarterVariant', () {
    test('returns dealerStarts when nothing is stored', () async {
      final result = await loadPersistedDefaultStarterVariant();
      expect(result, StarterVariant.dealerStarts);
    });

    test('returns stored value when it matches a known name', () async {
      SharedPreferences.setMockInitialValues({
        'default_starter_variant': 'oppositeChooserStarts',
      });
      final result = await loadPersistedDefaultStarterVariant();
      expect(result, StarterVariant.oppositeChooserStarts);
    });

    test(
      'returns dealerStarts fallback for unrecognised stored name',
      () async {
        SharedPreferences.setMockInitialValues({
          'default_starter_variant': 'notAVariant',
        });
        final result = await loadPersistedDefaultStarterVariant();
        expect(result, StarterVariant.dealerStarts);
      },
    );
  });

  // -----------------------------------------------------------------------
  // loadPersistedDefaultHeartsVariant
  // -----------------------------------------------------------------------
  group('loadPersistedDefaultHeartsVariant', () {
    test('returns onlyAfterPlayedHeart when nothing is stored', () async {
      final result = await loadPersistedDefaultHeartsVariant();
      expect(result, HeartsVariant.onlyAfterPlayedHeart);
    });

    test('returns stored value when it matches a known name', () async {
      SharedPreferences.setMockInitialValues({
        'default_hearts_variant': 'graduatedUnlock',
      });
      final result = await loadPersistedDefaultHeartsVariant();
      expect(result, HeartsVariant.graduatedUnlock);
    });

    test(
      'returns onlyAfterPlayedHeart fallback for unrecognised stored name',
      () async {
        SharedPreferences.setMockInitialValues({
          'default_hearts_variant': 'nope',
        });
        final result = await loadPersistedDefaultHeartsVariant();
        expect(result, HeartsVariant.onlyAfterPlayedHeart);
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

    test('setValue updates state and persists to SharedPreferences', () async {
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
      expect(
        prefs.getString('default_starter_variant'),
        'oppositeChooserStarts',
      );
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

    test('setValue updates state and persists to SharedPreferences', () async {
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
      expect(prefs.getString('default_hearts_variant'), 'graduatedUnlock');
    });
  });
}
