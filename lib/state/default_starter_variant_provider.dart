import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/starter_variant.dart';
import 'enum_preference_notifier.dart';

/// Default resolves to [StarterVariant.dealerStarts]. Override in
/// `ProviderScope.overrides` with `DefaultStarterVariantNotifier(initialVariant: ...)`
/// to seed the persisted value at startup — see
/// [loadPersistedSettings] and `main.dart`.
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
  String get settingsKey => 'starterVariant';

  @override
  String get settingsSection => 'ruleVariants';
}
