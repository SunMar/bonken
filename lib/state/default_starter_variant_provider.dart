import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/starter_variant.dart';
import 'settings_provider.dart';

/// Read-only view of the app-wide default [StarterVariant], derived from
/// [settingsProvider] (the single in-memory settings blob). Write via
/// `settingsProvider.notifier.setDefaultStarterVariant(...)`.
///
/// `RulesIconButton` overrides this provider (scoped to the pushed rules route)
/// with the session's committed variant — `overrideWithValue(...)` works
/// because this is a plain derived [Provider].
final defaultStarterVariantProvider = Provider<StarterVariant>(
  (ref) => ref.watch(settingsProvider.select((s) => s.defaultStarterVariant)),
);
