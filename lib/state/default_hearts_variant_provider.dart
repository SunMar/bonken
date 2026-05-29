import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hearts_variant.dart';
import 'enum_preference_notifier.dart';

const _kKey = 'default_hearts_variant';

/// Default resolves to [HeartsVariant.onlyAfterPlayedHeart]. Override in
/// `ProviderScope.overrides` with `DefaultHeartsVariantNotifier(initialVariant: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedDefaultHeartsVariant] and `main.dart`.
final defaultHeartsVariantProvider =
    NotifierProvider<DefaultHeartsVariantNotifier, HeartsVariant>(
      DefaultHeartsVariantNotifier.new,
    );

class DefaultHeartsVariantNotifier
    extends EnumPreferenceNotifier<HeartsVariant> {
  DefaultHeartsVariantNotifier({
    HeartsVariant initialVariant = HeartsVariant.onlyAfterPlayedHeart,
  }) : super(initialValue: initialVariant);

  @override
  String get prefsKey => _kKey;

  @override
  List<HeartsVariant> get values => HeartsVariant.values;

  @override
  HeartsVariant get fallback => HeartsVariant.onlyAfterPlayedHeart;
}

/// Reads the persisted [HeartsVariant] from [SharedPreferences].
///
/// Returns [HeartsVariant.onlyAfterPlayedHeart] when no value is stored or the
/// stored value can't be matched. Awaited in `main()` before [runApp].
Future<HeartsVariant> loadPersistedDefaultHeartsVariant() => loadPersistedEnum(
  key: _kKey,
  values: HeartsVariant.values,
  fallback: HeartsVariant.onlyAfterPlayedHeart,
);
