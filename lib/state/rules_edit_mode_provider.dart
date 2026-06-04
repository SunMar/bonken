import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How variant-sensitive rule blocks behave when the rules screen is opened
/// from different contexts.
enum RulesEditMode {
  /// Standalone rules page (home screen / deep link): cog icon is shown and
  /// opens the variant picker dialog to change the app-wide default.
  enabled,

  /// Score input screen: cog icon is hidden — the variant is fixed for the
  /// active round and cannot be changed here.
  hidden,

  /// Game screen: cog icon is shown but tapping it shows a snackbar directing
  /// the user to the 'Spel bewerken' button instead of opening the picker.
  /// The variant cannot be changed from this context; the interactive icon
  /// explains why rather than silently refusing.
  disabled,
}

/// Controls how variant-sensitive rule blocks render in [RulesBlockView].
///
/// Defaults to [RulesEditMode.enabled]. Overridden by [RulesIconButton] for
/// the pushed [RulesScreen] route when rules are opened from within a game.
final rulesEditModeProvider = Provider<RulesEditMode>(
  (ref) => RulesEditMode.enabled,
);
