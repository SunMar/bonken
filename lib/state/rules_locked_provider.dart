import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the rules screen is locked to a single committed rule set.
///
/// `false` (the default) on the standalone rules page (home / deep link): the
/// app-wide default variants are shown and variant-sensitive blocks expose a
/// settings icon plus the "Spelregel variant" alternative note.
///
/// Overridden to `true` in the [ProviderScope] that `RulesIconButton` wraps
/// around the pushed `RulesScreen` when rules are opened from within a game —
/// alongside overrides of the default-variant providers carrying the session's
/// values. While locked, the settings icon and the alternative note are hidden
/// (the player is committed to one rule set for the session).
final rulesLockedProvider = Provider<bool>((ref) => false);
