import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/starter_variant.dart';

const _kDefaultStarterVariantPrefsKey = 'default_starter_variant';

/// Default resolves to [StarterVariant.dealerStarts]. Override in
/// `ProviderScope.overrides` with `DefaultStarterVariantNotifier(initialVariant: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedDefaultStarterVariant] and `main.dart`.
final defaultStarterVariantProvider =
    NotifierProvider<DefaultStarterVariantNotifier, StarterVariant>(
      DefaultStarterVariantNotifier.new,
    );

class DefaultStarterVariantNotifier extends Notifier<StarterVariant> {
  DefaultStarterVariantNotifier({
    this.initialVariant = StarterVariant.dealerStarts,
  });

  /// Variant the notifier starts in. Pre-loaded from [SharedPreferences] in
  /// `main()` and injected via `defaultStarterVariantProvider.overrideWith(...)`,
  /// which avoids a first-frame flash.
  final StarterVariant initialVariant;

  @override
  StarterVariant build() => initialVariant;

  Future<void> setVariant(StarterVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultStarterVariantPrefsKey, variant.name);
  }
}

/// Reads the persisted [StarterVariant] from [SharedPreferences].
///
/// Returns [StarterVariant.dealerStarts] when no value is stored or the stored
/// value can't be matched. Awaited in `main()` before [runApp].
Future<StarterVariant> loadPersistedDefaultStarterVariant() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_kDefaultStarterVariantPrefsKey);
  if (value == null) return StarterVariant.dealerStarts;
  return StarterVariant.values.firstWhere(
    (v) => v.name == value,
    orElse: () => StarterVariant.dealerStarts,
  );
}
