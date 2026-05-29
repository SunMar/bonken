import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hearts_variant.dart';

const _kDefaultHeartsVariantPrefsKey = 'default_hearts_variant';

/// Default resolves to [HeartsVariant.onlyAfterPlayedHeart]. Override in
/// `ProviderScope.overrides` with `DefaultHeartsVariantNotifier(initialVariant: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedDefaultHeartsVariant] and `main.dart`.
final defaultHeartsVariantProvider =
    NotifierProvider<DefaultHeartsVariantNotifier, HeartsVariant>(
      DefaultHeartsVariantNotifier.new,
    );

class DefaultHeartsVariantNotifier extends Notifier<HeartsVariant> {
  DefaultHeartsVariantNotifier({
    this.initialVariant = HeartsVariant.onlyAfterPlayedHeart,
  });

  /// Variant the notifier starts in. Pre-loaded from [SharedPreferences] in
  /// `main()` and injected via `defaultHeartsVariantProvider.overrideWith(...)`,
  /// which avoids a first-frame flash.
  final HeartsVariant initialVariant;

  @override
  HeartsVariant build() => initialVariant;

  Future<void> setVariant(HeartsVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultHeartsVariantPrefsKey, variant.name);
  }
}

/// Reads the persisted [HeartsVariant] from [SharedPreferences].
///
/// Returns [HeartsVariant.onlyAfterPlayedHeart] when no value is stored or the
/// stored value can't be matched. Awaited in `main()` before [runApp].
Future<HeartsVariant> loadPersistedDefaultHeartsVariant() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_kDefaultHeartsVariantPrefsKey);
  if (value == null) return HeartsVariant.onlyAfterPlayedHeart;
  return HeartsVariant.values.firstWhere(
    (v) => v.name == value,
    orElse: () => HeartsVariant.onlyAfterPlayedHeart,
  );
}
