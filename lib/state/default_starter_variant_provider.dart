import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/starter_variant.dart';
import 'enum_preference_notifier.dart';

const _kKey = 'default_starter_variant';

/// Default resolves to [StarterVariant.dealerStarts]. Override in
/// `ProviderScope.overrides` with `DefaultStarterVariantNotifier(initialVariant: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedDefaultStarterVariant] and `main.dart`.
final defaultStarterVariantProvider =
    NotifierProvider<DefaultStarterVariantNotifier, StarterVariant>(
      DefaultStarterVariantNotifier.new,
    );

class DefaultStarterVariantNotifier
    extends EnumPreferenceNotifier<StarterVariant> {
  DefaultStarterVariantNotifier({
    StarterVariant initialVariant = StarterVariant.dealerStarts,
  }) : super(initialValue: initialVariant);

  @override
  String get prefsKey => _kKey;
}

/// Reads the persisted [StarterVariant] from [SharedPreferences].
///
/// Returns [StarterVariant.dealerStarts] when no value is stored or the stored
/// value can't be matched. Awaited in `main()` before [runApp].
Future<StarterVariant> loadPersistedDefaultStarterVariant() =>
    loadPersistedEnum(
      key: _kKey,
      values: StarterVariant.values,
      fallback: StarterVariant.dealerStarts,
    );
