import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils.dart';

/// Generic base for a [Notifier] that persists a single [Enum] value to
/// [SharedPreferences]. Subclasses supply the prefs key, the full values list
/// (for lookup by name), and the fallback default.
///
/// The [initialValue] is pre-loaded in `main()` and injected via
/// `provider.overrideWith(...)` to avoid a first-frame flash.
abstract class EnumPreferenceNotifier<T extends Enum> extends Notifier<T> {
  EnumPreferenceNotifier({required this.initialValue});

  /// Value the notifier starts in (pre-loaded in `main()`).
  final T initialValue;

  /// The [SharedPreferences] key under which the value is stored.
  String get prefsKey;

  /// All valid values of [T] — used to match a stored name back to an enum.
  List<T> get values;

  /// Returned when no value is stored or the stored name is unrecognised.
  T get fallback;

  @override
  T build() => initialValue;

  Future<void> setVariant(T variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, variant.name);
  }
}

/// Reads a persisted [T] from [SharedPreferences] using [key].
///
/// Returns [fallback] when no value is stored or the stored string does not
/// match any value in [values]. Awaited in `main()` before [runApp].
Future<T> loadPersistedEnum<T extends Enum>({
  required String key,
  required List<T> values,
  required T fallback,
}) async {
  final prefs = await SharedPreferences.getInstance();
  return enumByName(values, prefs.getString(key), fallback);
}
