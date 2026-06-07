import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_storage.dart';

/// Generic base for a [Notifier] that persists a single [Enum] value as a
/// field inside the versioned `settings` JSON blob (via [updateSettingsField]).
/// Subclasses supply the target key and optional section.
///
/// The [initialValue] is pre-loaded in `main()` and injected via
/// `provider.overrideWith(...)` to avoid a first-frame flash.
abstract class EnumPreferenceNotifier<T extends Enum> extends Notifier<T> {
  EnumPreferenceNotifier({required this.initialValue});

  /// Value the notifier starts in (pre-loaded in `main()`).
  final T initialValue;

  /// The key within the settings JSON (or within [settingsSection] if set).
  String get settingsKey;

  /// The sub-object key under which [settingsKey] lives, or `null` for a
  /// top-level field.
  String? get settingsSection => null;

  @override
  T build() => initialValue;

  Future<void> setValue(T value) async {
    state = value;
    await updateSettingsField(settingsSection, settingsKey, value.name);
  }
}
