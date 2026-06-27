import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hearts_variant.dart';
import 'settings_provider.dart';

/// Read-only view of the app-wide default [HeartsVariant], derived from
/// [settingsProvider] (the single in-memory settings blob). Write via
/// `settingsProvider.notifier.setDefaultHeartsVariant(...)`.
///
/// `RulesIconButton` overrides this provider (scoped to the pushed rules route)
/// with the session's committed variant — `overrideWithValue(...)` works
/// because this is a plain derived [Provider].
final defaultHeartsVariantProvider = Provider<HeartsVariant>(
  (ref) => ref.watch(settingsProvider.select((s) => s.defaultHeartsVariant)),
);
