import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hearts_variant.dart';
import 'enum_preference_notifier.dart';

/// Default resolves to [HeartsVariant.onlyAfterPlayedHeart]. Override in
/// `ProviderScope.overrides` with `DefaultHeartsVariantNotifier(initialVariant: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedSettings] and `main.dart`.
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
  String get settingsKey => 'heartsVariant';

  @override
  String get settingsSection => 'ruleVariants';
}
