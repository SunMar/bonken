/// Looks up an enum value by its [Enum.name]; returns null when [name] is null
/// or matches no value. The non-throwing probe shared by validators (e.g.
/// `validation.dart`'s settings gate).
T? enumByNameOrNull<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Looks up an enum value by its [Enum.name]. Returns [fallback] only when
/// [name] is **null** (the field is absent — e.g. a record predating it). A
/// present-but-unrecognized [name] is corrupt or forward-version data and
/// **throws** [FormatException]: callers sit behind a storage/import boundary
/// that turns the throw into a corrupt-data error rather than silently coercing
/// to the default. Use [enumByNameOrNull] when a non-throwing probe is wanted.
T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  return enumByNameOrNull(values, name) ??
      (throw FormatException('Unknown ${fallback.runtimeType} value', name));
}

/// Title for every "discard your edits" confirmation dialog.
const String kDiscardChangesTitle = 'Wijzigingen verwerpen';

/// Body text reused by every "discard your edits" confirmation dialog
/// (round input screen, edit-game screen, …).
const String kDiscardChangesMessage = 'Je wijzigingen gaan verloren.';

/// Title for the "discard new-game input" confirmation dialog.
const String kDiscardInputTitle = 'Invoer verwerpen';

/// Body text for the "discard new-game input" confirmation dialog.
const String kDiscardInputMessage = 'Je invoer gaat verloren.';

/// Label for every discard confirm button, tooltip, and action.
const String kDiscardLabel = 'Verwerpen';

/// Label for every save button and confirm action.
const String kSaveLabel = 'Opslaan';

/// Title for the game-screen "another game is still pending" info dialog.
const String kRoundIncompleteTitle = 'Ronde niet afgerond';

String formatDate(DateTime dt) {
  const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  const months = [
    'jan',
    'feb',
    'mrt',
    'apr',
    'mei',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
  final day = days[dt.weekday - 1];
  final h = _pad2(dt.hour);
  final m = _pad2(dt.minute);
  return '$day ${dt.day} ${months[dt.month - 1]} ${dt.year}  $h:$m';
}

String _pad2(int n) => n.toString().padLeft(2, '0');

/// `yyyy-MM-dd` date stamp for file names — locale-independent and sortable.
/// (Distinct from [formatDate], which is the human-facing Dutch format.)
String formatFileDate(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${_pad2(dt.month)}-${_pad2(dt.day)}';

/// `yyyy-MM-dd_HH-mm` timestamp for file names — locale-independent and
/// sortable. Minute resolution is enough to disambiguate exports.
String formatFileTimestamp(DateTime dt) =>
    '${formatFileDate(dt)}_${_pad2(dt.hour)}-${_pad2(dt.minute)}';

String formatScore(int score) => score > 0 ? '+$score' : '$score';

/// Recomputes [target]'s position after an item is moved from [oldIdx] to
/// [newIdx] in a list (using the same convention as [ReorderableListView]).
///
/// Returns the new index of whatever was previously at [target].  When
/// [target] equals [oldIdx], the returned value is the new index of the
/// moved item (i.e. [newIdx], normalised).
int adjustIndexAfterReorder(int oldIdx, int newIdx, int target) {
  if (target == oldIdx) return newIdx;
  var t = target;
  if (oldIdx < t) t -= 1;
  if (newIdx <= t) t += 1;
  return t;
}

/// Moves [fields]'s item from [oldIndex] to [newIndex] in place — using the
/// same convention as [ReorderableListView.onReorderItem], where [newIndex] is
/// already the post-removal insertion index — and returns the dealer index
/// adjusted to keep pointing at the same field, or null when [dealerIndex] is
/// null (random dealer).
///
/// Generic over the field type so both the new-game and edit-game screens share
/// one reorder body while [utils] stays framework-free.
int? reorderPlayerFields<T>(
  List<T> fields,
  int oldIndex,
  int newIndex,
  int? dealerIndex,
) {
  if (oldIndex == newIndex) return dealerIndex;
  fields.insert(newIndex, fields.removeAt(oldIndex));
  return dealerIndex == null
      ? null
      : adjustIndexAfterReorder(oldIndex, newIndex, dealerIndex);
}
